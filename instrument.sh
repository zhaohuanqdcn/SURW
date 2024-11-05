#!/bin/bash
set -e

# pushd e9patch; CC=gcc CXX=g++ ./build.sh; popd;

cp hooks/schedule_memops.c e9patch/examples;

BINARY=$(which $1 | xargs readlink -f)
BASENAME=$(basename $1)

CSV="${SEL_INSTR:=0}"
if [ ${SEL_INSTR} != "0" ]
then
	echo "D"
	CSV=$(readlink -f $CSV);
	cp $CSV e9patch
	CSV=$(basename $CSV .csv)
fi
echo CSV is $CSV
echo CSV is $SEL_INSTR

set +e
PIE=$(file $BINARY | grep "shared object")
EXTRA=
if [ "$PIE" = "" ]
then
    EXTRA="--option --mem-lb=0x300000"
fi
shift
set -e

pushd e9patch;
CC=gcc CXX=g++ ./e9compile.sh examples/schedule_memops.c

echo "Instrumenting..."

set -x

if [ $SEL_INSTR -eq 0 ]
then
"./e9tool" \
		-o "../${BASENAME}.inst" \
		-E '".plt"' -E '".plt.got"' -O2 --option --mem-granularity=4096 \
	  -M 'mem[0].access == rw && mem[0].base != %rsp && mem[0].seg == nil' \
	  -P 'mem_wri((static)addr, &mem[0], mem[0].size)@schedule_memops' \
	  -M 'mem[1].access == rw && mem[1].base != %rsp && mem[1].seg == nil' \
	  -P 'mem_wri((static)addr, &mem[1], mem[1].size)@schedule_memops' \
	  -M 'mem[0].access == r && mem[0].base != %rsp && mem[0].seg == nil' \
	  -P 'mem_ri((static)addr, &mem[0], mem[0].size)@schedule_memops' \
	  -M 'mem[1].access == r && mem[1].base != %rsp && mem[1].seg == nil' \
	  -P 'mem_ri((static)addr, &mem[1], mem[1].size)@schedule_memops' \
	  -M 'mem[0].access == w && mem[0].base != %rsp && mem[0].seg == nil' \
	  -P 'mem_wi((static)addr, &mem[0], mem[0].size)@schedule_memops' \
	  -M 'mem[1].access == w && mem[1].base != %rsp && mem[1].seg == nil' \
	  -P 'mem_wi((static)addr, &mem[1], mem[1].size)@schedule_memops' \
		--option --log=false $EXTRA $@ -- "$BINARY"
else
"./e9tool" \
		-o "../${BASENAME}.inst" \
		-E '".plt"' -E '".plt.got"' -O2 --option --mem-granularity=4096 \
	  -M "mem[0].access == rw && mem[0].base != %rsp && mem[0].seg == nil && addr == ${CSV}[0]" \
	  -P "mem_wri((static)addr, &mem[0], mem[0].size)@schedule_memops" \
	  -M "mem[1].access == rw && mem[1].base != %rsp && mem[1].seg == nil && addr == ${CSV}[0]" \
	  -P "mem_wri((static)addr, &mem[1], mem[1].size)@schedule_memops" \
	  -M "mem[0].access == r && mem[0].base != %rsp && mem[0].seg == nil && addr == ${CSV}[0]" \
	  -P "mem_ri((static)addr, &mem[0], mem[0].size)@schedule_memops" \
	  -M "mem[1].access == r && mem[1].base != %rsp && mem[1].seg == nil && addr == ${CSV}[0]" \
	  -P "mem_ri((static)addr, &mem[1], mem[1].size)@schedule_memops" \
	  -M "mem[0].access == w && mem[0].base != %rsp && mem[0].seg == nil && addr == ${CSV}[0]" \
	  -P "mem_wi((static)addr, &mem[0], mem[0].size)@schedule_memops" \
	  -M "mem[1].access == w && mem[1].base != %rsp && mem[1].seg == nil && addr == ${CSV}[0]" \
	  -P "mem_wi((static)addr, &mem[1], mem[1].size)@schedule_memops" \
		--option --log=false $EXTRA $@ -- "$BINARY"
fi
popd;
