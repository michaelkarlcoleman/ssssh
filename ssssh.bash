#!/bin/bash
# execute commands on or copy files from/to multiple hosts (similar to pdsh)

# ssssh, scripts for parallel remote execution and file copying
# Copyright (C) 2010  Tradebot Systems, Inc.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Initial implementation by Mike Coleman (who would rather write 100 lines of
# bash than fix 18000 lines of C any day of the week)

ssh_options="-oBatchMode=yes -oConnectTimeout=15"

usage() {
    cat <<EOF
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
                       "$ssh_options"]
  -n                   dry run--only print the commands that would be performed
  -A pull|push         make ssssh act like ssssh-pull/ssssh-push, respectively 
  -h                   print this help message and exit

Note that stderr from the commands is folded into stdout.  Also, command
status is not (currently) returned, so errors must be observed in some other
way.

Hostnames given with -x are not verified--they are just eliminated if they
would otherwise be included.  No effort is made to detect copies to/from the
same file on the same host, so don't do that.

EOF
    exit 1
}


die () {
    echo error: $@ 1>&2
    exit 1
}

program=$(basename $0)
program_args="$@"

max_procs=0			# unlimited
host_exclude_list=		# none excluded by default

case "$program" in
*-pull) action=pull;;
*-push) action=push;;
*)      action=sh;;
esac

while getopts "Ng:X:w:x:P:l:o:prnA:h" opt; do
    case $opt in
	g) gender_query="$OPTARG";;
	X) gender_exclude_query="$OPTARG";;
	w) host_list=$OPTARG;;
	x) host_exclude_list=$OPTARG;;
	N) disable_hostname=1;;
	P) max_procs=$OPTARG;;
	l) remote_user=$OPTARG;;
        o) ssh_options+=" -o$OPTARG";;
	p) preserve_times="-p";;
	r) recursive_copy="-r";;
	n) dry_run=1;;
	A) case "$OPTARG" in
	    pull|push) action=$OPTARG;;
	    *) die "-A arg must be 'pull' or 'push'";;
	   esac;;
	h) usage;;
	\?) exit 1;;
    esac
done

shift $(($OPTIND - 1))

case $action in
pull) [ $# -eq 2 ] || die exactly one source and one destination path required;;
push) [ $# -ge 2 ] || die at least one source path required;;
*) [ $# -ge 1 ] || die no command specified;;
esac

if [ -z "$gender_query" -a -z "$host_list" ]; then
    echo 1>&2 "one of -g or -w is required"
    usage
fi
if [ -n "$gender_query" -a -n "$host_list" ]; then
    echo 1>&2 "at most one of -g or -w is allowed"
    usage
fi
if [ -n "$gender_exclude_query" -a -n "$host_list" ]; then
    echo 1>&2 "at most one of -X or -w is allowed"
    usage
fi

# kind of a cop-out, but a vague error indication is better than nothing, since
# this will generally be run interactively
trap "{ die 'failure status returned (local or remote)'; }" EXIT
set -e				# stop immediately on any error status

##############################################################################

logger -t $program -p user.info \
    "USER=$USER ${SUDO_USER:+SUDO_USER=$SUDO_USER }PWD=$PWD $program $program_args" \
    || true

filt=cat
if [ -z "$disable_hostname" ]; then
    filt='sed -e "s/^/{}: /"'
fi
dry_run_prefix=${dry_run:+echo}

case $action in
pull|push) ssh_options+=" -B $preserve_times $recursive_copy";;
*)         ssh_options+=" -n -e none ${remote_user:+-l $remote_user}";;
esac

case $action in
pull)   target="$2"
	if [ -d "$target" ]; then
	    target="$2/$(basename $1)"
	fi
	command="scp $ssh_options ${remote_user:+$remote_user@}{}:$1 $target.{}";;
push)   command="scp $ssh_options ${@:1:${#@}-1} ${remote_user:+$remote_user@}{}:${@: -1}";;
*)      escargs=$(echo "$@" | sed -e 's/\"/\\"/g')
        command="ssh $ssh_options {} \"{ $escargs; }\"";;
esac

command="set -o pipefail; SSH_ASKPASS= $command 2>&1 | $filt || false"

if [ -n "$gender_query" ]; then
    if [ -n "$gender_exclude_query" ]; then
	nodeattr -c -X "$gender_exclude_query" "$gender_query"
    else
	nodeattr -c "$gender_query"
    fi
else
    echo "$host_list"
fi \
    | tr ',' '\n' \
    | sort \
    | uniq \
    | egrep -v -f <(echo "$host_exclude_list" | tr ',' '\n' \
                      | sed -e 's/^/^/' -e 's/$/$/') \
    | xargs -P "$max_procs" -r -n 1 -i \
        $dry_run_prefix bash --noprofile --norc -c "$command"

# NB: xargs will abort if a subcommand returns statuses 126, 127, 255 or the
# child is stopped or signaled.  In particular, ssh likes to return 255 under
# various conditions.
# 
# The pipe into $filt finesses this problem because by default the shell only
# returns the status of the last command in a pipeline, and both 'cat' and
# 'sed' will return 0 here unless something awful happens.

# Getting quoting right is difficult.  Our modest goal is to try to
# match the behavior of ssh.  Some test cases to try:
#
# ssssh -w localhost 'echo "||" | cat'
#
# ssssh -w localhost "cat /var/log/messages | fgrep -e 'one two three'"
#
# ssssh -w localhost sed -n -e 's/^root:.*$/xxx="7"/p' /etc/passwd
# ssssh -w localhost sed -n -e 's/^root:.*$/xxx=\"7\"/p' /etc/passwd
# ssssh -w localhost sed -n -e 's/^root:.*$/xxx="7;"/p' /etc/passwd

##############################################################################

# successful exit
# remove exit handler established above
trap - EXIT
exit 0
