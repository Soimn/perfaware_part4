package haversine_gen

import "core:fmt"
import "core:os"
import "core:math"
import "core:math/rand"

Char_IsAlpha :: proc(c: u8) -> bool
{
	return (u8((c & 0xDF) - 'A') <= u8('Z' - 'A'))
}

Char_IsDigit :: proc(c: u8) -> bool
{
	return (u8(c - '0') < 10)
}

String_MatchCaseInsensitive :: proc(a: string, b: string) -> bool
{
	result := (len(a) == len(b))

	for i := 0; result && i < len(a); i += 1
	{
		result = (a[i] == b[i] || (((a[i] ~ b[i]) & 0xDF) == 0 && Char_IsAlpha(a[i])))
	}

	return result
}

String_ParseU64 :: proc(s: string) -> (result: u64, ok: bool)
{
	result = 0

	for i in 0..<len(s)
	{
		if !Char_IsDigit(s[i]) do return 0, false
		else
		{
			digit := s[i] & 0x0F

			if (result*10)/10 != result || result*10 > max(type_of(result)) - u64(digit)
			{
				fmt.eprintln("sdfsdf")
				return 0, false
			}
			else
			{
				result = result*10 + u64(digit)
			}
		}
	}

	return result, true
}

Square :: proc(n: f64) -> f64
{
	return n*n
}

RadiansFromDegrees :: proc(deg: f64) -> f64
{
	return 0.01745329251994329577 * deg
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

main :: proc()
{
	earth_radius: f64 = 6372.8

	is_uniform: bool
	random_seed: u64
	pair_count: u64
	{
		print_usage := proc() { fmt.eprintf("Usage: %s [uniform/cluster] [random seed] [number of coordinate pairs to generate]\n", os.args[0]) }

		if len(os.args) != 4
		{
			//// ERROR
			fmt.eprintln("Invalid number of arguments")
			print_usage()
			return
		}
		else
		{
			if      String_MatchCaseInsensitive(os.args[1], "uniform") do is_uniform = true
			else if String_MatchCaseInsensitive(os.args[1], "cluster") do is_uniform = false
			else
			{
				//// ERROR
				fmt.eprintf("Invalid distribution '%s'\n", os.args[1])
				print_usage()
				return
			}

			{
				ok: bool
				random_seed, ok = String_ParseU64(os.args[2])
				if !ok
				{
					//// ERROR
					fmt.eprintf("Failed to parse seed '%s'\n", os.args[2])
					print_usage()
					return
				}
			}

			{
				pair_max := u64(100000000)

				ok: bool
				pair_count, ok = String_ParseU64(os.args[3])
				if !ok
				{
					//// ERROR
					fmt.eprintf("Failed to parse coordinate pair count '%s'\n", os.args[3])
					print_usage()
					return
				}
				else if pair_count > pair_max
				{
					//// ERROR
					fmt.eprintf("Too many pairs. Max is %d.\n", pair_max)
					print_usage()
					return
				}
			}
		}
	}

	expected_sum: f64 = 0

	pairs_left_in_cluster := (is_uniform ? max(u64) : 0)

	x_min: f64 = -180
	x_max: f64 = +180
	y_min: f64 = -90
	y_max: f64 = +90

	rand.reset(random_seed)

	flex_filename   := fmt.tprintf("data_%d_flex.json", pair_count)
	answer_filename := fmt.tprintf("data_%d_haveranswer.f64", pair_count)

	flex_file, flex_file_err     := os.open(flex_filename,   os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
	answer_file, answer_file_err := os.open(answer_filename, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)

	defer os.close(flex_file)
	defer os.close(answer_file)

	if flex_file_err != os.ERROR_NONE || answer_file_err != os.ERROR_NONE
	{
		//// ERROR
		fmt.eprintln("Failed to write data files")
		return
	}


	fmt.fprintf(flex_file, "{{\"pairs\":[\n")

	res_pair_count := 1/f64(pair_count)
	for i in 0..<pair_count
	{
		if pairs_left_in_cluster == 0
		{
			pairs_left_in_cluster = (pair_count/64) + 1
			x0 := rand.float64_range(-180, 180)
			x1 := rand.float64_range(-180, 180)
			y0 := rand.float64_range(-90, 90)
			y1 := rand.float64_range(-90, 90)

			x_min = min(x0, x1)
			x_max = max(x0, x1)
			y_min = min(y0, y1)
			y_max = max(y0, y1)
		}
		pairs_left_in_cluster -= 1

		x0 := rand.float64_range(x_min, x_max)
		y0 := rand.float64_range(y_min, y_max)
		x1 := rand.float64_range(x_min, x_max)
		y1 := rand.float64_range(y_min, y_max)

		dist := ReferenceHaversine(x0, y0, x1, y1, earth_radius)

		expected_sum += res_pair_count*dist

		fmt.fprintf(flex_file, "{{\"x0\":%.16f, \"y0\":%.16f, \"x1\":%.16f, \"y1\":%.16f}}%s\n", x0, y0, x1, y1, (i == pair_count-1 ? "" : ","))
		os.write(answer_file, (([^]u8)(&dist))[:size_of(dist)])
	}

	fmt.fprintf(flex_file, "]}\n")
	os.write(answer_file, (([^]u8)(&expected_sum))[:size_of(expected_sum)])

	fmt.printf("Method: %s\nRandom seed: %d\nPair count: %d\nExpected sum: %.16f\n", (is_uniform ? "uniform" : "cluster"), random_seed, pair_count, expected_sum)
}
