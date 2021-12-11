#! /usr/bin/env perl
#
# split-objump.pl -- Convert binaries into strings
#
# Example usage:
#     ./split-objump.pl /lib/x86_64-linux-gnu/libc-2.31.so
#
# Expected input is any file that objdump can disassemble. Output is
# a string of assembly, one string per text entry. The format is one
# that seems like it should be analyzable via pair-counting.
# (Just try it, you'll see...)
#
# This is a kind-of goofy thing to do, but lets just see what happens.
# We mostly avoid doing any analysis of the disassembly; for two
# reasons: (1) to see what happens if we don't, and (2) analysis is
# hard. (3) analysis is ultimately founded on human knowledge, and we
# are trying to avoid those foundations.
#
# It might be reasonable to do one little bit of analysis: do something
# with the addresses in jump & call insns. But, for now, we're not doing
# that. Exploring that is an XXX TODO item.
#
# The code here is somewhat Intel x86 specific, mostly to get a better
# cleaner feed.

my $object = $ARGV[0];

open DISM, "-|", "objdump -d --no-show-raw-insn $object" or die $0;

my $accum = "";

while(<DISM>) {
	chomp;

	# Skip over blank lines, miscellaneous information
	if (/^\//) { next; }
	if (/^Disassem/) { next; }
	if (/^$/) { next; }

	# When a new routine is reached, dump the completed line to STDOUT
	# Preface it by the routine name.
	if (/^\d+ /) {
		s/^\d+\s+//;
		s/>:$/> :/;
		if (not $accum =~ /^$/) {
			$accum =~ s/\s*$//;
			print "Line: >>$accum<<\n";
		}
		else {
			$accum = $_ . " NL ";
		}
		next;
	}

	# Cut off the leading address
	s/^\s*\w+:\s*//;

	# Some intel x96-specific stuff.
	# OK, we're going to give the system a leg up, and convert
	# addresses into smoething slightly more meaningful.  The
	# case being handled here looks like this:
	#    jmpq  *0x198f22(%rip)  # 1be0f8 <h_errlist@@GLIBC_2.2.5+0xfd8>
	# which will be converted into
	#    jmpq <h_errlist@@GLIBC_2.2.5+0xfd8>
	#
	if (/#/)
	{
		s/0x\w+\(%rip\)\s+#\s+\w+/ /;
		goto ACCUM;
	}

	# Some Intel x86 formatting: add assorted whitespace to
	# separate out tokens more cleanly.
	s/\*/* /;
	s/\(/ ( /;
	s/\)/ )/;
	s/\$/\$ /;
	s/,/ , /;
	s/:/ : /;

	# TODO: convert addresses to something comprehensible.
	# That is, something like
	#    jne    27ee8 <__gconv_get_alias_db@@GLIBC_PRIVATE+0x658>
	#    callq  25308 <malloc@plt>
	#    callq  25130 <*ABS*+0x8e110@plt>
	# should be convereted into some kind of ... reference.

ACCUM:
	print "Statement >>$_<<\n";

	# Cut off trailing whitespace
	s/\s*$//;

	# Accumulate the result.
	$accum .= $_ . ' NL ';
}

close DISM;