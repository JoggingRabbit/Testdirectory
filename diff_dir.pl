#!/usr/bin/perl
use strict;
use Getopt::Long;
use File::Find;
use File::Basename qw'basename';
#use Data::Dumper;
#use Digest::MD5;

my ($diff, $color, $all, $follow, $src, $dst, $src_regexp, $dst_regexp, %total) = (0, 0, 0, 0);
my %statu = ( 
    ok      => { flag => 'ok', color => 'green' }, 
    ng      => { flag => 'ng', color => 'red' },
    deleted => { flag => '--', color => 'red' },
    added   => { flag => '++', color => 'yellow' },
);

our $name;
*name = *File::Find::name;

GetOptions(
    'src=s'     => \$src, 
    'dst=s'     => \$dst, 
    'all'       => \$all,
    'color'     => \$color,
    'diff'      => \$diff,
    'follow'    => \$follow,
    'help'      => sub { print <DATA>; exit },
);
($src, $dst) = @ARGV if (@ARGV == 2);

do { -e or -r or die("Error: Can not access: $_\n    " . $!) } for ($src, $dst);
die "Error: source & destination must be directory" if ((! -d $src) || (! -d $dst));

# change . to \. to avoid matching issues
# / is not changed because we never use / 
# for matching boundary. in this script, 
# we use <> instead
 ($src_regexp = $src) =~ s<\.><\\.>g;
 ($dst_regexp = $dst) =~ s<\.><\\.>g;

print "Comparing $src & $dst\n";
File::Find::find(
    {
        wanted      => \&check_src,
        no_chdir    => 1,
        follow      => $follow,
    },
    $src,
);

File::Find::find(
    {
        wanted      => \&check_dst,
        no_chdir    => 1,
        follow      => $follow,
    },
    $dst,
);

printf "Total %d ok, %d ng, %d added, %d deleted.\n", $total{ok}, $total{ng}, $total{added}, $total{deleted};
foreach my $statu ('ng', 'added', 'deleted') {
    if ($total{$statu}) {
        print "All $statu files:\n";
        print "  ", $_, "\n" for @{$total{"${statu}_files"}};
    }
}

sub check_src {
    # return if $_ is not a file
    -f or return;
    #return if $_ is hidden or it's parent directory is hidden
=pod
    if -all is not enabled
    .a              return
    ./.a            return
    ./a             ok
    ./.a/b          return
    ./a/.b          return
    ./a/b           ok
=cut
    $all or m<^\.[^\./]|/\.[^\.]> and return;

    my ($file_basename, $file_src, $file_dst);
    $file_src = $name;
    ($file_basename = $file_src) =~ s<$src_regexp/*><>;
    ($file_dst = $file_src)      =~ s<$src_regexp/*><$dst/>;

    if (! -e $file_dst) {
        assign_file_statu('deleted', $file_basename);
    } else {
        my $file_src_md5 = get_MD5($file_src);
        my $file_dst_md5 = get_MD5($file_dst);
        if (defined $file_src_md5 && defined $file_dst_md5 && $file_src_md5 eq $file_dst_md5) {
            assign_file_statu('ok', $file_basename);
        } else {
            assign_file_statu('ng', $file_basename);
            system('diff', $file_src, $file_dst) if $diff;
        }
    }
}

sub check_dst {
    # this part is same as check_src
    -f or return;
    $all or m<^\.[^\./]|/\.[^\.]> and return;

    my ($file_basename, $file_src, $file_dst);
    $file_dst = $name;
    ($file_basename = $file_dst) =~ s<$dst_regexp/*><>;
    ($file_src = $file_dst)      =~ s<$dst_regexp/*><$src/>;

    # only check new added files
    if (! -e $file_src) {
        assign_file_statu('added', $file_basename);
    }
}

sub assign_file_statu {
    my ($statu, $file) = @_;
    $total{$statu} ++;
    push @{$total{ "${statu}_files" }}, $file;
    printf "[%s] %s\n", $color ? color_str($statu{$statu}{color}, $statu{$statu}{flag}) : $statu{$statu}{flag}, $file;
}

sub get_MD5 {
    my $file = shift;
    -e $file or return undef;
    my $ret  = `md5sum $file`;
    return (split(/\s+/, $ret))[0];
}

# Borrowed from: https://www.perturb.org/display/1167_Perl_ANSI_colors.html
# String format: '115', '165_bold', '10_on_140', 'reset', 'on_173', 'red', 'white_on_blue'
sub color {
	my $str = shift();

	# No string sent in, so we just reset
	if (!length($str) || $str eq 'reset') { return "\e[0m"; }

	# Some predefined colors
	my %color_map = qw(red 160 blue 21 green 34 yellow 226 orange 214 purple 93 white 15 black 0);
	$str =~ s|([A-Za-z]+)|$color_map{$1} // $1|eg;

	# Get foreground/background and any commands
	my ($fc,$cmd) = $str =~ /(\d+)?_?(\w+)?/g;
	my ($bc)      = $str =~ /on_?(\d+)/g;

	# Some predefined commands
	my %cmd_map = qw(bold 1 italic 3 underline 4 blink 5 inverse 7);
	my $cmd_num = $cmd_map{$cmd // 0};

	my $ret = '';
	if ($cmd_num)     { $ret .= "\e[${cmd_num}m"; }
	if (defined($fc)) { $ret .= "\e[38;5;${fc}m"; }
	if (defined($bc)) { $ret .= "\e[48;5;${bc}m"; }

	return $ret;
}

sub color_str {
    my ($color, $str) = @_;
    return $color ? color($color) . $str . color('reset') : $str;
}

__DATA__
[USAGE] 
    ./diff_dir.pl <source destination> [OPTIONS]
    This script can check difference between two directories
    eg: 
        ./diff_dir.pl a b  == ./diff_dir.pl -src a -dst b

[OPTIONS]
    -src        source directory
    -dst        destination directory
    -all        do not ignore entries starting with .
    -color      enable color
    -follow     causes symbolic links to be followed
    -diff       use system tool 'diff' to diff ng files
    -help       display this message