# NAME

[Mnet](https://metacpan.org/pod/Mnet) - Testable network automation and reporting

# SYNOPSIS

    # sample script to report Loopback0 address on cisco devices
    #
    #   demonstrates typical use of all major Mnet modules
    #   refer to perldoc for various Mnet modules for complete api info
    #
    #   use --help to list all options, or --help <option>
    #   use --device <address> to connect to device with logging
    #   use --batch <file.batch> to process one --device per line
    #   add --report csv:<file.csv> to create an output csv file
    #   add --record <file.test> to create a --device test file
    #   use --test --replay <file.test> to show script test diff

    # load modules
    use warnings;
    use strict;
    use Mnet::Batch;
    use Mnet::Expect::Cli::Ios;
    use Mnet::Log qw(DEBUG INFO WARN FATAL);
    use Mnet::Opts::Cli;
    use Mnet::Report::Table;
    use Mnet::Stanza;
    use Mnet::Test;

    # define --device name and --report output cli options
    #   options can also be set via Mnet environment variable
    Mnet::Opts::Cli::define({ getopt => "device=s" });
    Mnet::Opts::Cli::define({ getopt => "username=s" });
    Mnet::Opts::Cli::define({ getopt => "password=s" });
    Mnet::Opts::Cli::define({ getopt => "report=s" });

    # parse cli options, also parses Mnet environment variable
    my $cli = Mnet::Opts::Cli->new;

    # define output --report table, will include first of any errors
    #   use --report cli opt to output data as csv, json, sql, etc
    my $report = Mnet::Report::Table->new({
        columns => [
            device  => "string",
            error   => "error",
            ip      => "string",
        ],
        output  => $cli->report,
    });

    # handle concurrent --batch processing, parent exits when finished
    #   process a list of thousands of devices, hundreds at a time, etc
    $cli = Mnet::Batch::fork($cli);
    exit if not $cli;

    # ensure that errors are reported if script aborts for any reason
    $report->row_on_error({ device => $cli->device });

    # use log function and set up log object for device
    FATAL("missing --device") if not $cli->device;
    my $log = Mnet::Log->new({ log_id => $cli->device });
    $log->info("processing device");

    # create an expect ssh session to --device
    #   perldoc Mnet::Expect shows how to disable ssh host/key checks
    my $ssh = Mnet::Expect::Cli::Ios->new({
        spawn => [ "ssh", $cli->{device} ],
    });

    # retrieve config from ssh command, warn otherwise
    my $config = $ssh->command("show running-config");
    WARN("unable to read config") if not $config;

    # retrieve interface vlan 1 stanza from config
    my $loop = Mnet::Stanza::parse($config, qr/^interface loopback0$/i);

    # parse primary ip address from loopback config
    my $ip = undef;
    $ip = $1 if $loop and $loop =~ /^ ip address (\S+) \S+$/m;

    # report on parsed loopback interface ip addres
    $report->row({ device => $cli->device, ip => $ip });

    # finished
    exit;

# DESCRIPTION

The Mnet modules are for perl programmers who want to create testable network
automation and/or reporting scripts as simply as possible.

The main features of the Mnet perl modules are:

- Facilitate easy log, debug, alert and error output from automation scripts,
outputs can be redirected to per-device files
- Automation scripts can run in batch mode to concurrently process a list of
devices, using a simple command line argument and a device list file.
- Flexible config settings via command line, environment variable, and/or batch
device list files.
- Reliable automation of cisco IOS and other command line sessions, including
reliable authentication and command prompt handling.
- Report data from scripts can be output as plain .csv files, json, or sql.
- Record and replay connected command line sessions, speeding the development
of automation scripts and allowing for proper regression testing.

Most of the Mnet modules can be used independently of each other, unless
otherwise noted.

Refer to the individual Mnet modules listed in the SEE ALSO section below
for more detail.

# INSTALLATION

The Mnet perl modules should work in just about any unix perl environment.

The latest Mnet release can be installed from CPAN

    cpan install Mnet

Or downloaded and installed from [https://github.com/menzascripting/Mnet](https://github.com/menzascripting/Mnet)

    tar -xf Mnet-X.y.tar.gz
    cd Mnet-X.y
    perl Makefile.PL  # INSTALL_BASE=/specify/path
    make install

Be sure to update your PERL5LIB environment variable if you specified your
own install path.

# AUTHOR

The Mnet perl distribution has been created and is maintained by Mike Menza.
Mike can be reached via email at <mmenza@cpan.org>.

# COPYRIGHT AND LICENSE

Copyright 2006, 2013-2019 Michael J. Menza Jr.

Mnet is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see [http://www.gnu.org/licenses/](http://www.gnu.org/licenses/)

# SEE ALSO

[Mnet::Batch](https://metacpan.org/pod/Mnet::Batch)

[Mnet::Expect](https://metacpan.org/pod/Mnet::Expect)

[Mnet::Expect::Cli](https://metacpan.org/pod/Mnet::Expect::Cli)

[Mnet::Expect::Cli::Ios](https://metacpan.org/pod/Mnet::Expect::Cli::Ios)

[Mnet::Log](https://metacpan.org/pod/Mnet::Log)

[Mnet::Opts::Cli](https://metacpan.org/pod/Mnet::Opts::Cli)

[Mnet::Opts::Set::Debug](https://metacpan.org/pod/Mnet::Opts::Set::Debug)

[Mnet::Opts::Set::Quiet](https://metacpan.org/pod/Mnet::Opts::Set::Quiet)

[Mnet::Opts::Set::Silent](https://metacpan.org/pod/Mnet::Opts::Set::Silent)

[Mnet::Report::Table](https://metacpan.org/pod/Mnet::Report::Table)

[Mnet::Stanza](https://metacpan.org/pod/Mnet::Stanza)

[Mnet::Test](https://metacpan.org/pod/Mnet::Test)
