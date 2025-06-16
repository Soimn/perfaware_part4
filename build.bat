@echo off

setlocal

cd %~dp0

if not exist build mkdir build

call odin build src/haversine_gen.odin -file -out:build/haversine_gen.exe -o:speed -target-features:"avx2" -debug

call odin build src/haversine_test.odin -file -out:build/haversine_test.exe -o:speed -target-features:"avx2" -debug

call odin build src/math_test.odin -file -out:build/math_test.exe -o:speed -target-features:"avx2" -debug

endlocal
