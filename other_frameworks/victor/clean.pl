#!/usr/bin/perl -w
#
# $Id: clean.pl 383 2008-02-27 21:41:59Z michal $

=head1 NAME

clean.pl - clean html documents

=head1 SYNOPSIS

clean.pl [--model model] [--format format] file ...

=head1 OPTIONS

=over

=item B<-m|--model model>

Name of model file generated by learn.pl (defaults to the crf-model
configuration variable)

=item B<-o|--output-dir directory>

Directory where to save resulting *.clean files

=item B<-f|--format format>

Output format, one of HTML, CRF or Cleaneval.

=back

=cut

use strict;
use warnings;
use open ':locale';

use Victor::Getopt;
use Victor::Cfg;
use Victor::SplitHTML;
use Victor::Output::Cleaneval;
use Victor::Output::CRF;
use Victor::Output::HTML;
use Victor::LoadCRF;
use File::Basename;
use Victor::Temp;


my $opt_model;
my $opt_outdir = ".";
my $opt_format = "victor";
GetOptions(
	"_fileargs" => "1,",
	"m|model=s" => \$opt_model,
	"o|output-dir=s" => \$opt_outdir,
	"f|format=s" => \$opt_format,
);
$opt_model ||= cfg_get_string('crf-model');
$opt_format = lc($opt_format);
if (substr($opt_outdir, -1) ne "/") {
	$opt_outdir .= "/";
}

my $out_handler;
my $suffix;
if ($opt_format eq "victor") {
	$out_handler = \&output_html;
	$suffix = "html";
} elsif ($opt_format eq "crf") {
	# handled specially
	$suffix = "crf";
} elsif ($opt_format eq "cleaneval") {
	$out_handler = \&output_cleaneval;
	$suffix = "txt";
} else {
	print STDERR "unknown output format: $opt_format\n";
	print STDERR "available formats are: victor, crf, cleaneval\n";
	exit 1;
}

my $model = cfg_find_file("input model", "$opt_model", "", "models");

my ($tmp1, $tmp2);
{ 
	my $fh;
	($fh, $tmp1) = tempfile();
	close($fh);
	if ($opt_format ne "crf") {
		($fh, $tmp2) = tempfile();
		close($fh);
	}
}

foreach my $file (@ARGV) {
	my ($basename, $dir, $s) = fileparse($file, qr/\.html?/);
	my $outfile = ($opt_outdir ? $opt_outdir : $dir) . $basename . 
		".clean.$suffix";
	verbose(1, "$file -> $outfile\n");
	my @blocks;
	# XXX: this should be handled somehow cleaner...
	my $url;
	if ($opt_format eq "cleaneval") {
		open(my $fh, "<", $file);
		my $line = <$fh>;
		if ($line =~ /<text id="([^"]+)"/) {
			$url = $1;
		} else {
			print STDERR "warning: cleaneval output requested, but $file has no <text> tag\n";
		}
		close($fh);
	}
	# if the input file isn't precleaned, split_html will create
	# a temporary file
	my $precleaned = $file;
	split_html(\$precleaned, \@blocks);
	output_crf({train => 0, output => $tmp1, filename => $file }, \@blocks);
	run_crf_test($tmp1, $model, $tmp2 ? $tmp2 : $outfile);
	next if $opt_format eq "crf";
	load_crf($tmp2, \@blocks);
	&$out_handler({orig => $precleaned, output => $outfile, url => $url},
		\@blocks);
}

sub run_crf_test {
	my ($input, $model, $output) = @_;
	my $err = system("crf_test", "--verbose=2", "--output", $output,
		"--model", $model, $input);
	if ($err == -1) {
		die "cannot execute crf_test: $!\n";
	}
	if ($err) {
		print STDERR "crf_test returned error\n";
		exit $err >> 8;
	}
}
