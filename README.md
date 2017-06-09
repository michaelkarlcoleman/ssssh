# ssssh, a parallel shell/copy program

## ssssh

The ssssh program is a script written to replace pdsh (see pdsh(1)), a "parallel, distributed" shell often used for administering computational clusters.

It was written partly because it seemed easier than trying to fix some issues we encountered with pdsh, and partly for the pure entertainment value of building a parallel shell/copy program out of xargs and ssh.

Here are some simple ssssh usage examples:

    ### run 'uptime' on all Linux servers
    $ sudo ssssh -g server uptime
    server001:   2:05pm  up 15 days 17:06,  0 users,  load average: 0.00, 0.00, 0.00
    server021:   2:05pm  up 15 days 16:36,  0 users,  load average: 0.17, 0.07, 0.01
    server003:   2:05pm  up 15 days 16:45,  1 user,  load average: 0.00, 0.00, 0.00
    ...

You can pipe the output into other commands:

    ### look at hosts with longest uptimes 
    $ sudo ssssh -g lss cat /proc/uptime | sort -k2,2nr | less
    
    ### census of /etc/resolv.conf
    ### there are three flavors, 221 hosts have the most popular flavor
    $ sudo ssssh -g server -N md5sum /etc/resolv.conf | sort | uniq -c | sort -nr
        221 5154adf97ce87f59f9501531a51070c9  /etc/resolv.conf
         18 ac2657f61f47954bcc8286414df8d698  /etc/resolv.conf
          2 581d7997d40c49207cc58aeb2bee85ca  /etc/resolv.conf
          1 ssh: connect to host server032 port 22: Connection timed out

In the above example, we see that stderr for commands executed on the hosts is returned mixed in with stdout. Similarly, ssssh does not return an error status even if one of the host commands does. This may change in the future, but for now, be sure to look for error messages in the output.

    ### reboot servers, but not the one ssssh is running on (!)
    master# sudo ssssh -g server -x master reboot

As this example shows, sometimes you'll have to plan ahead to avoid doing something that will interfere with the execution of ssssh itself.

    ### run on just the specified hosts
    $ sudo ssssh -w server001,server007 ntpq -p

Here is the usage information:

    $ ssssh -h
    Usage: ssssh [<options>...] <command> [<command-arg>...]
           ssssh-pull [<options>...] <path> <local-directory>
           ssssh-push [<options>...] <path>... <remote-directory>
    
    ssssh runs a command on all of the specified hosts in parallel, using ssh.
    ssssh-pull copies the specified remote file or (with -r) directory from each 
    host into the specified local directory, adding a suffix of '.<hostname>' to 
    each.
    ssssh-push copies the specified local files or (with -r) directories into the
    specified remote directory on each host.
    
    Either -g or -w must be used to specify the host list.
    
      -g <gender-query>    query specifying hosts to include (see nodeattr(1))
      -X <gender-query>    query specifying hosts to exclude (see nodeattr(1))
      -w <hosts>           comma-separated list of hosts to include
      -x <hosts>           comma-separated list of hosts to exclude
      -N                   disable "hostname:" prefix on ssssh output lines
      -P <max-procs>       run up to max-procs processes in parallel (default:
                           unlimited)
      -l <username>        specify username to log in as on remote hosts
      -p                   preserves times and modes (ssssh-pull/-push)
      -r                   recursive copy (ssssh-pull/-push)
      -o <ssh-option>      append to ssh (or scp) -o options; may be specified 
                           multiple times [initial options are
                           "-oBatchMode=yes -oConnectTimeout=15"]
      -n                   dry run--only print the commands that would be performed
      -A pull|push         make ssssh act like ssssh-pull/ssssh-push, respectively 
      -h                   print this help message and exit 
 
 Note that stderr from the commands is folded into stdout.  Also, command
 status is not (currently) returned, so errors must be observed in some other
 way.
 
 Hostnames given with -x are not verified--they are just eliminated if they
 would otherwise be included.  No effort is made to detect copies to/from the
 same file on the same host, so don't do that.

## ssssh-pull and ssssh-push

These commands can be used to copy files from and to remote hosts, respectively. They are implemented with scp and work similarly, with two exceptions. ssssh-pull only takes one source argument, and it appends a dot and the hostname to the local target (so that files from multiple hosts are all given distinct names).

    # ssssh-pull -g cluster01 /etc/passwd .
    # ls
    passwd.svr01  passwd.svr03  passwd.svr05  passwd.svr07  passwd.svr09
    passwd.svr02  passwd.svr04  passwd.svr06  passwd.svr08  passwd.svr10
    
    # ssssh-push -g cluster01 /etc/motd /tmp

In our environment, massively parallel ssh/scp sessions sometimes hang. If this happens, you can Control-C and try again. For this reason and others, it may be safer to do the initial copy into a directory like /tmp and then a 'ssssh mv' to atomically move the file into its final position when pushing critical system files.

## The genders Database

To use the -g or -X flags of the ssssh commands, you must first set up a genders database. genders/libgenders is a library for querying a small text database of host information. The database itself lives in /etc/genders and has lines that look like this:

     nodename                attr[=value],attr[=value],...
     nodename1,nodename2,... attr[=value],attr[=value],...
     nodenames[A-B]          attr[=value],attr[=value],...

The first field indicates one or more hostnames, and the second is a comma-separated list of attributes with optional values. See libgenders(3) for more details.

The principal way to make use of the genders database is with the nodeattr command. This command is used to query the database and return the results in a useful format--a list of hosts separated by spaces, commas, or newlines. The ssssh commands call nodeattr when the -g flag is given.

## CAUTION

Tools like ssssh can let you get a lot of work done quickly, but anything that changes large groups of our hosts rapidly is risky, and ssssh is definitely a BFG in this game.  **If you make a big mistake, you will probably not have time to hit Control-C before the damage has been done on all of the selected hosts.**

So, you are encouraged to go slowly. Start with commands that look but don't change things. Before running a command on a large set of hosts, try it out first on one or two (using the -w flag), and look at the results. Use the -P flag (e.g., -P 1) to reduce parallelism, so that you'll have a fighting chance with that Control-C. Be careful with quoting and shell metacharacters, which can be difficult to predict--for complex tasks, create a script, copy it out, and then invoke it. Don't use ssssh inside a script or cron job. Consider whether running large sets of commands simultaneously may cause network or other I/O issues.

Those warnings notwithstanding, we hope you find ssssh a useful tool, as we have. Feedback is welcome.
