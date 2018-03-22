# makefile for assembling and linking x86_64 asm on mac

all: hello true

%: %.o
	ld -macosx_version_min 10.6 -o $@ -e main $<

%.o: %.asm
	nasm -f macho64 -o $@ $<
