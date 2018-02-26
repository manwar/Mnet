package Mnet::Opts::Cli;

=head1 NAME

Mnet::Opts::Cli

=head1 SYNOPSIS

The functions and methods in this module can be used by scripts to define and
parse command line options, as shown in the example below:

 # required to use this module
 use Mnet::Opts::Cli;

 # define --sample cli option
 Mnet::Opts::Cli::define({
     getopt   => 'sample=s',
     help_tip => 'set to input string',
 });

 # call in list context for cli opts object and any extra args
 my ($cli, @extras) = Mnet::Opts::Cli->new();

 # call in scalar context to disallow extra args
 $cli = Mnet::Opts::Cli->new();

 # access parsed cli options using method calls
 my $value = $cli->sample;

Refer to the Mnet::Opts and Mnet::Opts::Cli::Cache modules for more info.

=head1 TESTING

When used with the Mnet::Test --record option this module will save all cli
options defined with the record hash key set true in the specified Mnet::Test
file along with any extra arguments specified on the command line. For more
information about enabling the recording of individual options refer to the
define function in this module and the --default option for more information.

When the --replay option is used this module will load all cli options saved in
the specified Mnet::Test file then apply options specified on the command line
on top of the replayed options.

When the --replay option is used for an Mnet::Test file which was recorded with
extra arguments the extra arguments from the replay file will be used unless
there were extra arguments on the command line, in which case the command line
arguments will replace the arguments read from the replay file.

The --record option can be used to re-save a --replay file after applying new
command line options and/or extra arguments.

=cut

# required modules, inherits from Mnet::Opts
use warnings;
use strict;
use parent 'Mnet::Opts';
use Carp;
use Getopt::Long;
use Mnet::Dump;
use Mnet::Log::Conditional qw( DEBUG INFO WARN FATAL );
use Mnet::Opts::Cli::Cache;
use Mnet::Opts::Set;
use Mnet::Version;
use Storable;



# init global varviables in begin block
#   $defined: set before other init blocks call Mnet::Opts::Cli::defined()
#   @argv: copy of original @ARGV for Mnet::Opts::Cli->new, before script runs
BEGIN {
    my $defined = {};
    our @argv = @ARGV;
}



# init cli options used by this module
INIT {

    # init stdout file handle to bypass Mnet::Test output capture if loaded
    our $stdout = undef;
    if ($INC{"Mnet/Test.pm"}) {
        $stdout = $Mnet::Test::stdout;
    } else {
        open($stdout, ">&STDOUT");
    }

    # define --default cli option
    Mnet::Opts::Cli::define({
        getopt      => 'default:s',
        help_tip    => 'reset recordable options or extra args',
        help_text   => '
            use --default with --record to reset named options to default
            use --default with no option name to reset extra args to default
            use --help for individual options to check if they are recordable
            warning issued if --default is specified for non-recordable options
            this option works from the command line only
        ',
    });

    # define --help cli option
    Mnet::Opts::Cli::define({
        getopt      => 'help:s',
        help_tip    => 'display tips, or text for matching options',
    });

    # define --version cli option
    Mnet::Opts::Cli::define({
        getopt      => 'version',
        help_tip    => 'display version and system information',
    });

# finished init code block
}



sub define {

=head1 Mnet::Opts::Cli::define(\%specs)

This function may be used during initialaztion to define cli options which can
be parsed by the Mnet::Opts->cli class method in this module, as in the example
which follows that define a --sample string option:

 use Mnet::Cli::Opts;
 Mnet::Opts::Cli::define({ getopt => 'sample=s' });

A warning results if an option with the same name has already been defined.

The following Getopt::Long option specification types are supported:

 opt    --opt       boolean option, set true if --opt is set
 opt!   --[no]opt   negatable option, returns false if --noopt is set
 opt=i  --opt <i>   required integer, warns if input value is not set
 opt:i  --opt [i]   optional integer, returns null if value not set
 opt=s  --opt <s>   required string, warns if input value is not set
 opt:s  --opt [s]   optional string, returns null if value not set

The following keys in the specs input hash reference argument are supported:

 getopt     - required option name and type, refer to perldoc Getopt::Long
 default    - default value for option, defaults to undefined
 help_tip   - short tip text to show in --help list of available options
 help_text  - longer help text to show in --help for specific options
 recordable - set so that option is saved to Mnet::Test record/replay file

Refer to perldoc Getopt::Long for more information.

=cut

    # read input option definition specs
    my $specs = shift or croak("missing specs arg");
    croak("invalid specs hash ref") if ref($specs) ne "HASH";

    # check for required getopt key in input specs, note opt name
    croak("missing specs hash getopt key") if not defined $specs->{getopt};
    croak("invalid specs hash getopt value") if $specs->{getopt} !~ /^(\w+)/;
    my $opt = $1;

    # abort if option was already defined
    #   options defined differently in multiple places would cause problems
    croak("option $opt defined by $Mnet::Opts::Cli::defined->{$opt}->{caller}")
        if exists $Mnet::Opts::Cli::defined->{$opt};

    # copy input specs to global var holding defined options
    $Mnet::Opts::Cli::defined->{$opt} = Storable::dclone($specs);

    # set caller for defined option
    $Mnet::Opts::Cli::defined->{$opt}->{caller} = caller;

    # set help_usage for defined option
    #   note that this aborts with an error for unsupported Getopt::Long types
    $Mnet::Opts::Cli::defined->{$opt}->{help_usage}
        = _define_help_usage($Mnet::Opts::Cli::defined->{$opt}->{getopt});

    # finished Mnet::Opts::Cli::define
    return;
}



sub _define_help_usage {

# $help_usage = _define_help_usage($getopt)
# purpose: output help usage syntax given input getopt string
# $getopt: input option specification in Getopt::Long format
# $help_usage: output option usage syntax, used for --help output
# note: aborts with an error for unsupported Getopt::Long specs

    # read input getopt spec string
    my $getopt = shift // croak "missing getopt arg";

    # init output help usage string for supported getopt types
    my $help_usage = undef;
    if ($getopt =~ /^(\w+)$/)   { $help_usage = $1;       }
    if ($getopt =~ /^(\w+)\!$/) { $help_usage = "[no]$1"; }
    if ($getopt =~ /^(\w+)=i$/) { $help_usage = "$1 <i>"; }
    if ($getopt =~ /^(\w+):i$/) { $help_usage = "$1 [i]"; }
    if ($getopt =~ /^(\w+)=s$/) { $help_usage = "$1 <s>"; }
    if ($getopt =~ /^(\w+):s$/) { $help_usage = "$1 [s]"; }

    # abort if unable to determine help usage
    croak("invalid or unsupported specs hash getopt value $getopt")
        if not defined $help_usage;

    # finished _define_help_usage, return help_usage
    return $help_usage;
}


sub new {

=head1 $self = Mnet::Opts::Cli->new()

=head1 S< > or ($self, @extras) = Mnet::Opts::Cli->new()

The class method may be used to retrieve an options object containing defined
options parsed from the command line and an array contining any extra command
line arguments.

If called in list context this method will return an opts object containing
values for defined options parsed from the command line followed by a list of
any other extra arguments that were present on the command line.

 use Mnet::Opts::Cli;
 my ($cli, @extras) = Mnet::Opts::Cli->new();

If called in scalar context a warning will be issued if extra command line
arguments exist.

 use Mnet::Opts::Cli;
 my $cli = Mnet::Opts::Cli->new();

Options are applied in the following order:

 - child Mnet::Batch command lines
 - command line
 - replayed command line
 - Mnet environment variable
 - Mnet::Opts::Set use pragmas
 - Mnet::Opts::Cli::define default key

Note that warnings are not issued for unknown options that may be set for other
scripts in the Mnet environment variable. Also note that the Mnet environment
variable is not parsed if the --test option is set on the command line.

The perl ARGV array is not modified by this module.

=cut

    # read input class, warn if not called as a class method
    my $class = shift // croak("missing class arg");
    croak("invalid call to class new") if ref $class;

    # read batch child opts from Mnet::Opts::Cli::batch() only
    #   refer to Mnet::Opts::Cli::batch() for more information
    my $batch_argv = shift;
    croak("invalid call with batch_argv")
        if defined $batch_argv and caller ne "Mnet::Opts::Cli";

    # returned cached cli options and extra args, if set from prior call
    if (Mnet::Opts::Cli::Cache::get()) {
        my ($opts, @extras) = Mnet::Opts::Cli::Cache::get();
        my $self = bless $opts, $class;
        return wantarray ? ($self, @extras) : $self;
    }

    # configure how command line parsing will work
    Getopt::Long::Configure(qw/
        no_auto_abbrev
        no_getopt_compat
        no_gnu_compat
        no_ignore_case
        pass_through
        prefix=--
    /);

    # note all getopt definitions, set from Mnet::Opt::Cli::define()
    my @definitions = ();
    foreach my $opt (keys %{$Mnet::Opts::Cli::defined}) {
        push @definitions, $Mnet::Opts::Cli::defined->{$opt}->{getopt}
    }

    # parse options from command line, also note extra args on command line
    #   remove -- as the first extra options, used to stop option parsing
    my ($cli_opts, @extras) = ({}, @Mnet::Opts::Cli::argv);
    Getopt::Long::GetOptionsFromArray(\@extras, $cli_opts, @definitions);
    shift @extras if defined $extras[0] and $extras[0] eq "--";

    #   output extra cli arg warning when not called to return extras args
    die "invalid extra arguments @extras\n" if $extras[0] and not wantarray;

    # merge child process batch_argv options on top of cli options
    my $batch_opts = {};
    Getopt::Long::GetOptionsFromString($batch_argv, $batch_opts, @definitions)
        if defined $batch_argv;
    $cli_opts->{$_} = $batch_opts->{$_} foreach keys %$batch_opts;

    # enable silent pragma based on --silent, --help, and --version cli options
    #   this is done so Mnet::Test and Mnet::Log has access to this
    #   remove silent pragma if --nosilent option was set on cli
    if ($cli_opts->{silent}
        or defined $cli_opts->{help} or $cli_opts->{version}) {
        Mnet::Opts::Set::enable("silent");
    } elsif (defined $cli_opts->{silent} and not $cli_opts->{silent}) {
        delete $INC{"Mnet/Opts/Set/Silent.pm"};
    }

    # enable quiet pragma based on --quiet cli options
    #   this is done so Mnet::Test and Mnet::Log has access to this
    #   remove quiet and silent pragmas if --noquiet option was set on cli
    if ($cli_opts->{quiet}) {
        Mnet::Opts::Set::enable("quiet");
    } elsif (defined $cli_opts->{quiet} and not $cli_opts->{quiet}) {
        delete $INC{"Mnet/Opts/Set/Quiet.pm"};
        delete $INC{"Mnet/Opts/Set/Silent.pm"};
    }

    # parse options set via Mnet::Opts::Set pragma sub-modules
    my $pragma_opts = Mnet::Opts::Set::pragmas();

    # output --help if set on command line and exit
    #   disable log entries during help by setting --quiet in cli cache
    if (defined $cli_opts->{help}) {
        Mnet::Opts::Cli::Cache::set({ quiet => 1 });
        my $help = _new_help($cli_opts->{help});
        syswrite $Mnet::Opts::Cli::stdout, "$help\n";
        exit 1;
    }

    # output --version info if set on command line and exit
    #   disable log entries during version by setting --quiet in cli cache
    if ($cli_opts->{version}) {
        Mnet::Opts::Cli::Cache::set({ quiet => 1 });
        my $info = Mnet::Version::info();
        $info =~ s/^/  /mg;
        syswrite $Mnet::Opts::Cli::stdout, "\n$info\n";
        exit 1;
    }

    # init cached opts from cli opts only for now, and initial logger
    #   this allows --debug settings from cli when reading replay data
    #   this is ok because log env opts are not parse if --replay is set
    my $init_log_opts = $pragma_opts;
    $init_log_opts->{$_} = $cli_opts->{$_} foreach keys %$cli_opts;
    Mnet::Opts::Cli::Cache::set($init_log_opts);
    my $log = Mnet::Log::Conditional->new();

    # parse options from --replay file only if --test is also set
    #   force a re-read of the replay file for forked batch children
    #   ignore replay file options that were defined without record key set
    my $replay_opts = {};
    if (defined $cli_opts->{replay}) {
        my $test_data = Mnet::Test::data($cli_opts, "force");
        foreach my $opt (sort keys %{$Mnet::Opts::Cli::defined}) {
            next if not $Mnet::Opts::Cli::defined->{$opt}->{recordable};
            next if not exists $test_data->{opts}->{$opt};
            $replay_opts->{$opt} = $test_data->{opts}->{$opt};
            my $opt_dump = Mnet::Dump::line($replay_opts->{$opt});
            $log->debug("new found replay opt $opt = $opt_dump");
        }
    }

    # parse options from Mnet env variable if --record and --replay are not set
    #   ignore warnings for env options that might not be defined at the moment
    my $env_opts = {};
    if (defined $ENV{Mnet}
        and not defined $cli_opts->{replay}
        and not defined $cli_opts->{record}) {
        eval {
            local $SIG{__WARN__} = "IGNORE";
            Getopt::Long::GetOptionsFromString(
                $ENV{Mnet}, $env_opts, @definitions
            );
        }
    }

    # prepare list to hold log entries, which will be output later
    #   log_entries keyed by opt name, set source keyword followed by dump
    #   to avoid catch-22 of properly logging opts before log opts are parsed
    my $log_entries = {};

    # apply options in order of precedence, refer to perldoc for this method
    #   apply opt in order of precedence: cli, replay, env, pragma, and default
    #   log_entries hash ref is updated for each option, with source and dump
    my $opts = {};
    foreach my $opt (sort keys %{$Mnet::Opts::Cli::defined}) {
        my $defined_opt = $Mnet::Opts::Cli::defined->{$opt};

        # options can be reset to with --default cli option
        if (defined $cli_opts->{default} and $cli_opts->{default} eq $opt) {
            $log_entries->{$opt} = "def";
            $opts->{$opt} = $defined_opt->{default};

        # options from cli have highest priority
        #   this includes child batch command line options
        } elsif (exists $cli_opts->{$opt}) {
            $log_entries->{$opt} = "cli";
            $opts->{$opt} = $cli_opts->{$opt};

        # recordable options from replay file are next
        } elsif (exists $replay_opts->{$opt}) {
            $log_entries->{$opt} = "cli";
            $opts->{$opt} = $replay_opts->{$opt};

        # then environment variables, skipped for --record and --replay
        } elsif (exists $env_opts->{$opt}) {
            $log_entries->{$opt} = "env";
            $opts->{$opt} = $env_opts->{$opt};

        # then pragma options, which can be overridden by the above
        } elsif (exists $pragma_opts->{$opt}) {
            $log_entries->{$opt} = "use";
            $opts->{$opt} = $pragma_opts->{$opt};

        # finally defined default value for option is used
        } else {
            $log_entries->{$opt} = "def";
            $opts->{$opt} = $defined_opt->{default};
        }

        # note log entry for the current option, with any notes
        $log_entries->{$opt} .= " " . Mnet::Dump::line($opts->{$opt});

    # finish parsing loop through defined options
    }

    # create logger object after updating cli opt cache with parsed opts
    Mnet::Opts::Cli::Cache::set($opts);
    $log = Mnet::Log::Conditional->new($opts);

    # log parsed options, as per prepared log_entries array
    #   log_entries keys are opt names, set to source keyword followed by dump
    #   default opts identified with 'def' log entry prefix are logged to debug
    foreach my $opt (sort keys %$log_entries) {
        my $log_entry = $log_entries->{$opt};
        $log_entry =~ s/(\S+)/opt $1 ${opt} =/;
        if ($log_entry =~ /^opt def/) {
            $log->debug("new parsed $log_entry");
        } elsif (not $Mnet::Opts::Cli::defined->{$opt}->{recordable}
            and ($opts->{replay} or $opts->{record} or $opts->{batch})) {
            $log->notice("new parsed $log_entry");
        } else {
            $log->info("new parsed $log_entry");
        }
    }

    # get test data hash ref from Mnet::Test module
    #   init to empty dummy hash ref if Mnet::Test not loaded
    my $test_data = {};
    $test_data = Mnet::Test::data() if $INC{"Mnet/Test.pm"};

    # update opts in test in case --record will be used later
    #   skip opts that were not defined with the record key enabled
    $test_data->{opts} = {};
    foreach my $opt (sort keys %$opts) {
        next if not $Mnet::Opts::Cli::defined->{$opt}->{recordable};
        my $value = $opts->{$opt};
        my $default = $Mnet::Opts::Cli::defined->{$opt}->{default};
        next if not defined $value and not defined $default;
        next if defined $value and defined $default and $value ne $default;
        $log->debug("new record cli opt $opt will be saved to Mnet::Test data");
        $test_data->{opts}->{$opt} = $opts->{$opt};
    }

    # use extra args from command line, otherwise look for them in replay file
    #   replace extra args in replay file if we have new set of extra from cli
    if (defined $extras[0]) {
        $log->debug("new extra cli args will record from command line");
        $test_data->{extras} = \@extras;
    } elsif (defined $opts->{default} and $opts->{default} eq "") {
        $log->debug("new extra cli args will record as reset to --default");
        delete $test_data->{extras};
    } elsif (exists $test_data->{extras}) {
        $log->debug("new extra cli args will replay from Mnet::Test data");
        @extras = @{$test_data->{extras}};
    }

    # log extra arguments in effect for rest of execution
    $log->info("new parsed cli arg (extra) = ".Mnet::Dump::line($_))
        foreach @extras;

    # update cli opt cache for the final time, including extra comme line args
    Mnet::Opts::Cli::Cache::set($opts, @extras);

    # disable collection of stdout/stderr if --record or --test are not set
    #   this is an optimization, to avoid saving output in memory if not needed
    if ($INC{"Mnet/Test.pm"}
        and not $opts->{record} and not $opts->{test}) {
        Mnet::Test::disable();
    }

    # create new cli opts object using the current class
    my $self = bless $opts, $class;

    # finished new method, return cli opts object and extra args or just object
    return wantarray ? ($self, @extras) : $self;
}



sub _new_help {

# $output = _new_help($help)
# purpose: output help for all defined options
# $help: from --help opt, null shows tip list, otherwise help text on matches
# $output: help text ready to display


    # read input --help opt value
    my $help = shift // "";

    # init output help text
    my $output = "\n";

    # output list of help usage tips, one line per option
    if ($help eq "") {

        # calculate width to align usage and tip columns
        my $width = 0;
        foreach my $opt (sort keys %{$Mnet::Opts::Cli::defined}) {
            my $defined_opt = $Mnet::Opts::Cli::defined->{$opt};
            next if $width > length($defined_opt->{help_usage});
            $width = length($defined_opt->{help_usage});
        }

        # prepare sub to output help usage and tip aligned into columns
        sub _new_help_tip {
            my ($width, $defined_opt) = (shift, shift);
            my $usage = $defined_opt->{help_usage};
            my $tip = $defined_opt->{help_tip} // "";
            return sprintf(" --%-${width}s   $tip\n", $usage);
        }

        # output Mnet options
        $output .= "Mnet options:\n\n";
        foreach my $opt (sort keys %{$Mnet::Opts::Cli::defined}) {
            my $defined_opt = $Mnet::Opts::Cli::defined->{$opt};
            next if $defined_opt->{caller} !~ /^Mnet(::|$)/;
            $output .= _new_help_tip($width, $defined_opt);
        }

        # output non-Mnet options
        $output .= "\nOther options:\n\n";
        foreach my $opt (sort keys %{$Mnet::Opts::Cli::defined}) {
            my $defined_opt = $Mnet::Opts::Cli::defined->{$opt};
            next if $defined_opt->{caller} =~ /^Mnet(::|$)/;
            $output .= _new_help_tip($width, $defined_opt);
        }


    # output long form help text for options matching input --help value
    } else {

        # loop through all options
        foreach my $opt (sort keys %{$Mnet::Opts::Cli::defined}) {
            my $defined_opt = $Mnet::Opts::Cli::defined->{$opt};

            # skip option names that don't match input --help text
            next if $opt !~ /\Q$help\E/;

            # output usage for current command
            my $usage = $defined_opt->{help_usage};
            $output .= " --$usage";

            # output if option is saved in --record files
            my $recordable = "\n";
            $recordable = "   (recordable)\n" if $defined_opt->{recordable};
            $output .= $recordable;

            # output tip for current command, if defined
            my $tip = $defined_opt->{help_tip};
            $output .= "\n   $tip\n" if defined $tip;
            $tip = "   $tip\n" if $tip ne "";

            # output long form help text for current command, if defined
            my $text = $defined_opt->{help_text};
            if (defined $text) {
                $text =~ s/(^(\n|\s)+|(\n|\s+)$)//g;
                $text =~ s/^\s*/    /mg;
                $output .= "\n$text\n";
            }

        # continue looping through
        }

    # finished creating help output
    }

    # finished _new_help function, return output help text
    return $output;
}



sub batch {

# Mnet::Opts::Cli::batch($batch_argv)
# purpose: called to apply child batch command line to cached cli opts/args
# $batch_argv: batch child command line in Getopts::Long string format
# note: this is meant to be called from Mnet::Batch::fork only

    # read input child batch command line
    my $batch_argv = shift // croak("missing batch_argv arg");
    DEBUG("batch called, batch_argv = $batch_argv");

    # clear cached cli options and args
    Mnet::Opts::Cli::Cache::set(undef);

    # parse batch child command lines
    Mnet::Opts::Cli->new($batch_argv);

    # finished Mnet::Opts::Cli::batch
    return;
}



=head1 SEE ALSO

 Getopt::Long
 Mnet
 Mnet::Dump
 Mnet::Log::Conditional
 Mnet::Opts::Cli::Cache
 Mnet::Opts::Set
 Mnet::Test
 Mnet::Version

=cut

# normal package return
1;

