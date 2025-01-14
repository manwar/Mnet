package Mnet::Tee;

=head1 NAME

Mnet::Tee - Redirect stdout and stderr to a file

=head1 SYNOPSIS

    # use this module on it's own
    use Mnet::Tee;
    Mnet::Tee::file($file);

    # or use with command line options
    use Mnet::Tee;
    use Mnet::Opts::Cli;
    my $cli = Mnet::Opts::Cli->new;

=head1 DESCRIPTION

This module captures all stdout and stderr output from an executing script and
saves that output to the specified file. Be sure to call Mnet::Tee::file() or
parse cli options before generating any other output.

The variables stdout and stderr can be imported from this module to use for
output that should not be captured by the Mnet::Tee module. The pause and
unpause functions in this module can be used for this purpose also.

Note that output captured by this module is stored in memory. That could be
a problem for scripts that generate gigabytes of stdout and/or stderr output.

The perl tie command is used to implement the functionality of this module.

=cut

# required modules
#   perl 5.10 may be requried for tie to capture stdout and stderr
use warnings;
use strict;
use 5.010;
use Carp;
use Exporter qw( import );
use Mnet::Log::Conditional qw( DEBUG INFO WARN FATAL NOTICE );
use Mnet::Opts::Cli::Cache;

# export function names
our @EXPORT_OK = qw( $stderr $stdout );



# begin block to initialize capture of stdout and stderr
BEGIN {

    # original stderr and stdout for bypassing output captured by Mnet::Tee
    open(our $stderr, ">&STDERR");
    open(our $stdout, ">&STDOUT");

    # init global scalar variable to accumulate stdout+stderr test outputs
    my ($test_outputs, $test_paused) = ("", undef);

    # init filehandle that may be used to --tee redirected data
    #   also init buffer to hold first line, which may be notice log entry
    #       this is needed especially for batch child with --tee in batch list
    #       other implementations should call Mnet::Tee::file before any output
    my ($fh, $fh_line1) = (undef, undef);

    # declare tie contructor used to capture stdout/stderr handles
    sub TIEHANDLE {
        my ($class, $fh) = (shift, shift);
        return bless({ fh => $fh }, $class);
    }

    # declare tie method triggered for print to handles
    sub PRINT {
        my $self = shift;
        &{$self->{fh}}(@_);
        return 1;
    }

    # declare tie method triggered for printf to handles
    sub PRINTF {
        my $self = shift;
        return $self->PRINT(sprintf(@_));
    }

    # declare tie method triggered for write to handles
    sub WRITE {
        my $self = shift;
        my ($buffer, $length ,$offset) = (shift, shift, shift // 0);
        return $self->PRINT(substr($buffer, $offset, $length));
        return 1;
    }

    # create copied of stderr and stdout to be used for output from tie subs
    open(my $stderr_fh, ">&STDERR");
    open(my $stdout_fh, ">&STDOUT");

    # declare sub used to save --tee output to a file
    #   write new text to file if file handle is already open
    #   otherwise check for --tee option and open file if necessary
    #   save first output line if not ready to write to file yet
    sub tee_file {
        my $text = shift // return;
        if ($Mnet::Tee::fh) {
            syswrite $Mnet::Tee::fh, $text;
        } else {
            my $cli = Mnet::Opts::Cli::Cache::get({});
            if ($cli->{tee}) {
                open($Mnet::Tee::fh, ">", $cli->{tee})
                    or die "unable to open --tee $cli->{tee}, $!\n";
                syswrite $Mnet::Tee::fh, $Mnet::Tee::fh_line1
                    if defined $Mnet::Tee::fh_line1;
                syswrite $Mnet::Tee::fh, $text;
            } elsif (not defined $Mnet::Tee::fh_line1) {
                $Mnet::Tee::fh_line1 = $text;
            }
        }
    }

    # declare sub used to enable capture of stderr and stdout using tie command
    sub tie_enable {
        tie(*STDERR => 'Mnet::Tee' , sub {
            my $text = "@_";
            $Mnet::Tee::test_outputs .= $text if not $Mnet::Tee::test_paused;
            tee_file($text);
            return
                if $INC{"Mnet/Opts/Set/Silent.pm"}
                and not $INC{"Mnet/Opts/Set/Quiet.pm"};
            syswrite $stderr_fh, $text;
        });
        tie(*STDOUT => 'Mnet::Tee' , sub {
            my $text = "@_";
            $Mnet::Tee::test_outputs .= $text if not $Mnet::Tee::test_paused;
            tee_file($text);
            return if $INC{"Mnet/Opts/Set/Quiet.pm"};
            return if $INC{"Mnet/Opts/Set/Silent.pm"};
            syswrite $stdout_fh, $text;
        });
    }

    # use tie to capture stderr and stdout to global test outputs variable
    Mnet::Tee::tie_enable();

    # declare sub used from Mnet::Expect to temporarily untie filehandles
    sub tie_disable {
        untie *STDERR;
        untie *STDOUT;
    }

# finished begin block
}



# define --tee cli option
INIT {
    Mnet::Opts::Cli::define({
        getopt      => 'tee:s',
        help_tip    => 'redirect stdout and stderr to file',
        help_text   => '
            script stdout and stderr can be redirected to a --tee file
            note that --tee with --batch merges all parent/child output in file
            this option works from the command line only
            refer to perldoc Mnet::Tee for more info
        ',
        norecord    => 1,
    }) if $INC{"Mnet/Opts/Cli.pm"};
}



sub batch_fork {

# Mnet::Tee::test_reset()
# purpose: reset accumulated test outputs buffered first line output
# note: called after new Mnet::Batch::fork child, to get rid of parent output

    # reset accumulated test outputs to null
    $Mnet::Tee::test_outputs = "";
    $Mnet::Tee::fh_line1 = undef;
    return;
}



sub file {

=head2 file

    Mnet::Tee::file($file)

The function can be used to write output to the specified file, including all
prior output. The script will abort if unable to open the new file.

=cut

    # read input filename
    my $file = shift // croak "missing file arg";
    DEBUG("file starting");

    # abort if unable to open new output file
    DEBUG("file opening file $file");
    open(my $fh, ">", $file) or FATAL("error writing to file $file, $!");

    # close any old output file and use this one going forward
    if (defined $Mnet::Tee::fh) {
        DEBUG("file closing old file handle");
        close $Mnet::Tee::fh;
    }

    # update file handle used by tie functions in begin block
    DEBUG("file updating file handle");
    $Mnet::Tee::fh = $fh;

    # write all prior output to the new file
    DEBUG("file saving prior test output");
    syswrite $Mnet::Tee::fh, $Mnet::Tee::test_outputs;

    # finished file function
    DEBUG("file finished");
    return;
}



sub test_outputs {

# $test_outputs = Mnet::Tee::test_outputs()
# purpose: return a string containing all accumulated prior test outputs
# $outputs: string containing all prior stdout and stderr test outputs

    # return all prior stdout and stderr outputs
    return $Mnet::Tee::test_outputs;
}



sub test_pause {

# Mnet::Tee::test_pause()
# purpose: stop the accumulation of new test output from stdout and stderr
# note: this does not affect output being sent to a file

    # disable accumulation of captured output
    $Mnet::Tee::test_paused = 1;
}



sub test_paused {

# $test_paused = Mnet::Tee::test_paused()
# purpose: returns current pause/pause status
# $paused: true if the accumulation of new stdout/stderr test output is paused

    # return status of stdout and stderr test output accumulation
    return $Mnet::Tee::test_paused;
}



sub test_unpause {

# Mnet::Tee::test_unpause()
# purpose: starts the accumulation of new test output from stdout and stderr

    # enable accumulation of captured output
    $Mnet::Tee::test_paused = 0;
}



=head1 SEE ALSO

L<Mnet>

L<Mnet::Opts::Cli>

L<Mnet::Test>

=cut

# normal end of package
1;

