default: build

build:
	zig build

run:
	zig build run

check:
	zig fmt --check src/**/*.zig

test:
	zig build test
