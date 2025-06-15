package haversine_test

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:math"
import intrin "base:intrinsics"

import w32 "core:sys/windows"

rdtsc :: intrin.read_cycle_counter

Haversine_Pair :: struct
{
	x0: f64,
	y0: f64,
	x1: f64,
	y1: f64,
}

EARTH_RADIUS :: f64(6372.8)

ApproximatelyEquals :: proc(a: f64, b: f64) -> bool
{
	epsilon := f64(0.00000001)
	diff := a - b
	return (diff < epsilon && diff > -epsilon)
}

RadiansFromDegrees :: proc(deg: f64) -> f64
{
	return 0.01745329251994329577 * deg
}

Square :: proc(n: f64) -> f64
{
	return n*n
}

ReferenceHaversine :: proc(x0: f64, y0: f64, x1: f64, y1: f64, earth_radius: f64) -> f64
{
	lat1 := y0
	lat2 := y1
	lon1 := x0
	lon2 := x1

	dLat := RadiansFromDegrees(lat2 - lat1)
	dLon := RadiansFromDegrees(lon2 - lon1)
	lat1 = RadiansFromDegrees(lat1)
	lat2 = RadiansFromDegrees(lat2)
    
	a := Square(math.sin(dLat/2.0)) + math.cos(lat1)*math.cos(lat2)*Square(math.sin(dLon/2))
	c := 2.0*math.asin(math.sqrt(a))

	return earth_radius * c
}

HaversineSum :: proc($haversine_proc: proc(f64, f64, f64, f64, f64) -> f64) -> (proc([]Haversine_Pair) -> f64)
{
	return proc(pairs: []Haversine_Pair) -> f64
	{
		sum: f64 = 0

		res_pair_count := 1/f64(len(pairs))
		for i in 0..<len(pairs)
		{
			sum += res_pair_count*haversine_proc(pairs[i].x0, pairs[i].y0, pairs[i].x1, pairs[i].y1, EARTH_RADIUS)
		}

		return sum
	}
}

HaversineVerify :: proc($haversine_proc: proc(f64, f64, f64, f64, f64) -> f64) -> (proc([]Haversine_Pair, []f64, f64) -> (u64, bool))
{
	return proc(pairs: []Haversine_Pair, answers: []f64, expected_sum: f64) -> (error_count: u64, wrong_sum: bool)
	{
		sum: f64 = 0

		res_pair_count := 1/f64(len(pairs))
		for i in 0..<len(pairs)
		{
			dist := haversine_proc(pairs[i].x0, pairs[i].y0, pairs[i].x1, pairs[i].y1, EARTH_RADIUS)

			sum += res_pair_count*dist

			if !ApproximatelyEquals(dist, answers[i])
			{
				error_count += 1
			}
		}

		wrong_sum = (!ApproximatelyEquals(sum, expected_sum))

		return error_count, wrong_sum
	}
}

Test_Case :: struct
{
	name: string,
	sum_proc: proc([]Haversine_Pair) -> f64,
	verify_proc: proc([]Haversine_Pair, []f64, f64) -> (u64, bool),
}

TestCases := [?]Test_Case{
	{ "Reference", HaversineSum(ReferenceHaversine), HaversineVerify(ReferenceHaversine) }
}

main :: proc()
{
	if len(os.args) != 3
	{
		fmt.eprintf("Invalid number of arguments.\nUsage: %s [json input] [answer file]\n", os.args[0])
		return
	}

	json_input, json_input_ok       := os.read_entire_file(os.args[1])
	answers_input, answers_input_ok := os.read_entire_file(os.args[2])

	if !json_input_ok
	{
		fmt.eprintf("Failed to read json input file '%s'\n", os.args[1])
		return
	}

	if !answers_input_ok
	{
		fmt.eprintf("Failed to answers file '%s'\n", os.args[2])
		return
	}

	pair_count := len(answers_input)/8 - 1

	answers      := (([^]f64)(&answers_input[0]))[:pair_count]
	expected_sum := (([^]f64)(&answers_input[0]))[pair_count]

	pairs := make([]Haversine_Pair, pair_count)
	{
		j := len("{\"pairs\":[")

		for i in 0..<pair_count
		{
			vals := [4]f64{}

			for k in 0..<len(vals)
			{
				for j < len(json_input) && json_input[j] != ':' do j += 1

				start := j + 1

				for j < len(json_input) && json_input[j] != (k == len(vals)-1 ? '}' : ',') do j += 1
				
				v, err := strconv.parse_f64(string(json_input[start:j]))
				vals[k] = v
				if !err do fmt.println(string(json_input[start:j]))
			}

			pairs[i] = { x0 = vals[0], y0 = vals[1], x1 = vals[2], y1 = vals[3] }
		}
	}

	rdtsc_freq: u64 = 0
	{
		perf_freq: w32.LARGE_INTEGER
		w32.QueryPerformanceFrequency(&perf_freq)

		start_qpc: w32.LARGE_INTEGER
		w32.QueryPerformanceCounter(&start_qpc)

		start_tsc := u64(rdtsc())

		end_qpc: w32.LARGE_INTEGER
		end_tsc: u64
		for
		{
			w32.QueryPerformanceCounter(&end_qpc)
			end_tsc = u64(rdtsc())

			if end_qpc - start_qpc > perf_freq/4 do break
		}

		qpc := u64(end_qpc - start_qpc)
		tsc := end_tsc - start_tsc

		rdtsc_freq = (tsc * u64(perf_freq)) / qpc
	}

	fmt.printf("Source JSON: %f MB\n", f64(len(json_input)) / (1 << 20))
	fmt.printf("Parsed: %f MB (%d pairs)\n", f64(pair_count*size_of(Haversine_Pair)) / (1 << 20), pair_count)
	fmt.printf("Estimated RDTSC frequency: %d Hz\n\n", rdtsc_freq)

	for test_case in TestCases
	{
		fmt.printf("%s\n===============================================\n", test_case.name)
		
		error_count, wrong_sum := test_case.verify_proc(pairs, answers, expected_sum)

		min_t: u64 = max(u64)
		max_t: u64 = 0
		sum_t: u64 = 0
		count_t: u64 = 0
		idle_t: u64 = 0
		idle_cutoff: u64 = 5*rdtsc_freq
		{
			for idle_t < idle_cutoff
			{
				start_t := u64(rdtsc())
				sum := test_case.sum_proc(pairs)
				end_t := u64(rdtsc())

				t := end_t - start_t
				min_t = min(min_t, t)
				max_t = max(max_t, t)

				sum_t   += t
				count_t += 1

				if idle_cutoff < t do idle_cutoff = 2*t

				if t == min_t do idle_t  = 0
				else          do idle_t += t

				wrong_sum |= (!ApproximatelyEquals(sum, expected_sum))
			}
		}

		avg_t := sum_t/count_t

		min_ms := f64(min_t*1000)/f64(rdtsc_freq)
		max_ms := f64(max_t*1000)/f64(rdtsc_freq)
		avg_ms := f64(avg_t*1000)/f64(rdtsc_freq)

		fmt.printf("min: %010d (%.5f ms) %.5f GB/s\n", min_t, min_ms, (f64(pair_count*size_of(Haversine_Pair)) / (min_ms*f64(1 << 30)/1000)))
		fmt.printf("max: %010d (%.5f ms) %.5f GB/s\n", max_t, max_ms, (f64(pair_count*size_of(Haversine_Pair)) / (max_ms*f64(1 << 30)/1000)))
		fmt.printf("avg: %010d (%.5f ms) %.5f GB/s\n", avg_t, avg_ms, (f64(pair_count*size_of(Haversine_Pair)) / (avg_ms*f64(1 << 30)/1000)))

		fmt.printf("%s sum, %d individual errors\n\n", (wrong_sum ? "wrong" : "correct"), error_count)
	}
}
