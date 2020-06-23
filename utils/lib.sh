#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /CoreOS/php/Library/utils
#   Description: Library with various utility functions for php tests
#   Author: David Kutalek <dkutalek@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = php
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

php/utils

=head1 DESCRIPTION

Library with various utility functions for php tests.

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 VARIABLES

Below is the list of global variables for general use.

=over

=item phpFPM_CONFDIR

Directory where php-fpm's other config files and modules are stored.

=item phpFPM_CONF

Path to php-fpm's main config file.

=item phpFPM_LOGDIR

Directory where php-fpm's log files are stored.

=item phpFPM_ERROR_LOG

Path to php-fpm's www error log file.

=back

=cut

which php-fpm > /dev/null 2>&1 && phpFPM_CONFDIR=$(rpm -qf `which php-fpm` -ql | grep 'php-fpm.d$' | grep '/etc/' | grep -v '/register.content/')
test -n "$phpFPM_CONFDIR" && phpFPM_CONF=$(rpm -qf `which php-fpm` -ql | grep 'php-fpm.conf$' | grep '/etc/' | grep -v '/register.content/' | grep -v 'nginx')
test -n "$phpFPM_CONFDIR" && phpFPM_LOGDIR=$(rpm -qf `which php-fpm` -ql | grep '/log/php-fpm' | grep -v '/register.content/')
test -n "$phpFPM_CONFDIR" && phpFPM_ERROR_LOG=${phpFPM_LOGDIR}/www-error.log

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 phpPopulateSources

Populates PACKAGE_SOURCES variable with list of srpm packages for:
 * packages listed in PACKAGES & COLLECTIONS variables, OR
 * packages given as arguments (if arguments given)

=over

=back

Populates PACKAGE_SOURCES and asserts result.

Returns 0 when srpms found, 1 otherwise.

=cut

phpPopulateSources() {
    # resulting variable
    PACKAGE_SOURCES=''

    # using
    local PKGS="$@"
    if [ $# -lt 1 ]; then PKGS="$PACKAGES $REQUIRES $COLLECTIONS"; fi

    local P ; local PS ; local I
    for P in $PKGS; do
        PS=$(rpm -q $P --qf '%{SOURCERPM}')

        # resulting list should be without duplicates
        for I in $PACKAGE_SOURCES; do [ "_$I" = "_$PS" ] && continue 2; done

        PACKAGE_SOURCES="$PACKAGE_SOURCES $PS"
    done
    PACKAGE_SOURCES="$(echo $PACKAGE_SOURCES | sed 's/^ //')"
    [ ! -z "$PACKAGE_SOURCES" ] && { rlPass "phpPopulateSources: PACKAGE_SOURCES='$PACKAGE_SOURCES'"; return 0; } && return 0
    rlFail "phpPopulateSources: no srpms found!"
    return 1
}

true <<'=cut'
=pod

=head2 phpAssertFileOrigin

Takes a list of absolute file names and asserts that every one is provided by
some package built from any of srpm defined in SOURCE_PACKAGES.
IOW asserts that all given files have origin in known srpm.

Files without origin in given srpm will be reported as warn if
its basename is not present in any binary rpm from PACKAGES (probably not relevant file),
or as error if it is.

=over

=back

Always run phpPopulateSources first or fill SOURCE_PACKAGES by other means.

Passes when all relevant files originates from known srpms, fails otherwise.
Runs rlAssertEquals as last command and returns its return value.

=cut

phpAssertFileOrigin() {
    date

    if [ $# -lt 1 ]; then
        rlLogError "rlAssertFileOrigin: You have to supply at least one absolute path"
        return 1
    fi
    [ -z "$PACKAGE_SOURCES" ] && { rlFail "PACKAGE_SOURCES empty. Use phpPopulateSources first."; return 0; } && return 1

    local F ; local FS ; local PS ; local FOUND ; local R=0
    for F in $@; do
        FS=$(rpm -qf $F --qf '%{SOURCERPM}')
        FOUND=0
        for PS in $PACKAGE_SOURCES; do
            [ "_$PS" = "_$FS" ] && {
                echo "$F has origin in $PS"
                FOUND=1
                R=$((R+1))
                break
            }
        done
        [ $FOUND -eq 0 ] && {
            local relevant=0
            [ _"$rpmqlpackages" = _ ] && rpmqlpackages="$(rpm -ql $PACKAGES $REQUIRES)"
            if echo $rpmqlpackages | grep -e $(basename $F)\$; then
                rlLog "File $F is relevant (PACKAGES file: $(echo $rpmqlpackages | grep -e `basename $F`\$))"
                rlLogError "Origin not found for relevant file $F"
                relevant=1
            fi
            if [ $relevant -eq 0 ]; then
                rlLog "File $F is not relevant to any package in PACKAGES"
                rlLogWarning "Origin not found for irrelevant file $F (probably ok)"
                R=$((R+1))
            fi
        }
    done
    rlAssertEquals "phpAssertFileOrigin: $# files given, $R ok" $# $R

    date
}

true <<'=cut'
=pod

=head2 phpMainPackage

Searches in $PACKAGES $COLLECTIONS for php main package, that is the one
containing mod_php and called 'php' in the simplest case.

=over

=back

Populates php_RPM, php_BIN, php_INI and php_MOD_PHP_CONF variables and asserts result.

Returns 0 when main package was found, 1 otherwise.

=cut

phpMainPackage () {
    for P in $PACKAGES $COLLECTIONS $REQUIRES; do
        if rpm -q --provides $P | grep -q 'mod_php ='; then
            php_RPM=$P
            rlPass "phpMainPackage: php_RPM=$php_RPM"
            php_BIN=$(rpm -ql ${php_RPM}-cli | grep bin/php$)
            rlPass "phpMainPackage: php_BIN=$php_BIN"
            php_INI="$(rpm -ql $php_RPM-common | grep 'php.ini$' | grep -v 'register\.content' | head -1)"
            local grep_cmd="rpm -ql $php_RPM | grep \"${httpCONFDIR}/conf.d/.*php.*\.conf$\""
            php_MOD_PHP_CONF="$(eval $grep_cmd)"
            # line below does not work some times - not sure why
            # php_MOD_PHP_CONF="$(rpm -ql $php_RPM | grep \"${httpCONFDIR}/conf.d/.*php.*\.conf$\")"
            rlRun '[ ! -z "$php_INI" ]' 0 "phpMainPackage: php_INI=$php_INI"
            rlRun '[ ! -z "$php_MOD_PHP_CONF" ]' 0 "phpMainPackage: php_MOD_PHP_CONF=$php_MOD_PHP_CONF"
            if rlIsRHEL ">=7"; then
                rlLog "phpMainPackage: two mod_php config files on RHEL >= 7!"
                grep_cmd="rpm -ql $php_RPM | grep \"${httpCONFDIR}/conf.modules.d/.*php.*\.conf$\""
                php_MOD_PHP_CONF_MODULES="$(eval $grep_cmd)"
                # line below does not work some times - not sure why
                # php_MOD_PHP_CONF_MODULES="$(rpm -ql $php_RPM | grep \"${httpCONFDIR}/conf.modules.d/.*php.*\.conf$)$\""
                rlRun '[ ! -z "$php_MOD_PHP_CONF_MODULES" ]' 0 "phpMainPackage: php_MOD_PHP_CONF_MODULES=$php_MOD_PHP_CONF_MODULES"
            fi
            return 0
        fi
    done
    rlFail "phpMainPackage: not found, php_RPM, php_BIN, php_INI, php_MOD_PHP_CONF and php_MOD_PHP_CONF_MODULES undefined"
    return 1
}


true <<'=cut'
=pod

=head2 phpChooseModPhpConfig

Goes through ${httpCONFDIR}/conf.d/*php.conf and chooses one relevant for $php_RPM.
WARNING: It deletes other *php.conf files, so later rlFileRestore is needed!
All configs are backuped via rlFileBackup - including chosen one.
Needs php_RPM to contains valid PHP base package (e.g. php).

=over

=back

Always run phpMainPackage first or populate php_RPM by other means.

Populates php_MOD_PHP_CONF and php_MOD_PHP_CONF_MODULES variables and asserts result.

Returns 0 when relevant config(s) was found, 1 otherwise.

=cut

phpChooseModPhpConfig () {
    local C ; local S ; local F=0
    for C in ${httpCONFDIR}/conf.d/*php.conf; do
        rlFileBackup $C
        if [ "_$C" != "_$php_MOD_PHP_CONF" ]; then
            S="DELETED"
            rm -f $C
        else
            S="ACTIVE "
            F=1
        fi
        echo "$S - $C"
    done
    if rlIsRHEL ">=7"; then
        for C in ${httpCONFDIR}/conf.modules.d/*php.conf; do
            rlFileBackup $C
            if [ "_$C" != "_$php_MOD_PHP_CONF_MODULES" ]; then
                S="DELETED"
                rm -f $C
            else
                S="ACTIVE "
                F=$((F+1))
            fi
            echo "$S - $C"
        done
        [ $F -eq 2 ] && { rlPass "phpChooseModPhpConfig: activated $php_MOD_PHP_CONF + $php_MOD_PHP_CONF_MODULES"; return 0; } && return 0
    else
        [ $F -eq 1 ] && { rlPass "phpChooseModPhpConfig: activated $php_MOD_PHP_CONF"; return 0; } && return 0
    fi
    rlFail "phpChooseModPhpConfig: mod_php config(s) not found";
    return 1
}

true <<'=cut'
=pod

=head2 phpAssertModPhpLoaded

Inspects running httpd processes for mod_php library (libphp*.so or librh-php*.so).

=over

=back

Passes when lsof indicates usage of libphp*.so or librh-php*.so in any one running httpd process.

=cut

phpAssertModPhpLoaded () {
    sleep 5
    local HTTPD_PIDS ; local MOD_PHP_SO
    HTTPD_PIDS=$(ps aux | grep httpd | grep -v grep | sed 's/^[^ ]* *\([0-9]*\).*$/\1/' | tr '\n' ',' | sed 's/,$//')
    MOD_PHP_SO=$(lsof -p "$HTTPD_PIDS" | grep 'lib\(rh-\)*php.*\.so' | sed 's/^.*  *\(.*\)$/\1/' | sort | uniq)
    rlLog "httpd processes: $HTTPD_PIDS"
    rlLog "loaded mod_php library: $MOD_PHP_SO"
    rlRun "[ \"_$MOD_PHP_SO\" != '_' ]" 0 "mod_php is loaded into httpd"
}

true <<'=cut'
=pod

=head2 phpAssertModPhpNotLoaded

Inspects running httpd processes for mod_php library (libphp*.so or librh-php*.so).
Asserts pass when mod_php is NOT loaded!

=over

=back

Passes when lsof does NOT indicate usage of libphp*.so librh-php*.so in any one running httpd process.

=cut

phpAssertModPhpNotLoaded () {
    sleep 5
    local HTTPD_PIDS ; local MOD_PHP_SO
    HTTPD_PIDS=$(ps aux | grep httpd | grep -v grep | sed 's/^[^ ]* *\([0-9]*\).*$/\1/' | tr '\n' ',' | sed 's/,$//')
    MOD_PHP_SO=$(lsof -p "$HTTPD_PIDS" | grep 'lib\(rh-\)*php.*\.so' | sed 's/^.*  *\(.*\)$/\1/' | sort | uniq)
    rlLog "httpd processes: $HTTPD_PIDS"
    rlLog "loaded mod_php library: $MOD_PHP_SO"
    rlRun "[ \"_$MOD_PHP_SO\" = '_' ]" 0 "mod_php is NOT loaded into httpd"
}

true <<'=cut'
=pod

=head2 phpPrintLoadedModPhpLibs

Inspects running httpd processes and prints all used php*.so files.
Which means also all present php modules from php subpackages.

=over

=back

Always returns 0.

=cut

phpPrintLoadedModPhpLibs () {
    sleep 5
    local HTTPD_PIDS
    HTTPD_PIDS=$(ps aux | grep httpd | grep -v grep | sed 's/^[^ ]* *\([0-9]*\).*$/\1/' | tr '\n' ',' | sed 's/,$//')
    echo "$(lsof -p $HTTPD_PIDS | grep 'php.*\.so' | sed 's/^.*  *\(.*\)$/\1/' | sort | uniq)"
}

true <<'=cut'
=pod

=head2 phpPrintLoadedPhpFpmLibs

Inspects running php-fpm processes and prints all used php*.so files.
Which means also all present php modules from php subpackages.

=over

=back

Always returns 0.

=cut

phpPrintLoadedPhpFpmLibs () {
    sleep 5
    local PHP_FPM_PIDS
    PHP_FPM_PIDS=$(ps aux | grep php-fpm | grep -v grep | sed 's/^[^ ]* *\([0-9]*\).*$/\1/' | tr '\n' ',' | sed 's/,$//')
    echo "$(lsof -p $PHP_FPM_PIDS | grep ' [^ ]*lib[^ ]*php[^ ]*\.so' | sed 's/^.*  *\(.*\)$/\1/' | sort | uniq)"
}

true <<'=cut'
=pod

=head2 phpClearSessionDir

Clears php session dir as defined in $php_INI (session.save_path).
Asserts removal fo session files when directory found.

=over

=back

Always returns 0.

=cut

phpClearSessionDir () {
    local SESSION_DIR=$(grep '^[^;]*session.save_path' $php_INI | sed 's/^.*= *\(.*\)/\1/' | tr -d '"')
    if [ -z $SESSION_DIR ]; then
        SESSION_DIR=$(rpm -qla $PACKAGES $COLLECTIONS $REQUIRES \
        | grep '/lib/php/session'  | grep -v 'register.content' | head -1)
    fi
    rlLog "phpClearSessionDir: SESSION_DIR=$SESSION_DIR (local variable)"
    ls -l $SESSION_DIR
    [ ! -z $SESSION_DIR ] && rlRun "rm -f $SESSION_DIR/*"
    return 0
}


true <<'=cut'
=pod

=head2 phpIniSet

Takes name and value and defines it into $php_INI.
Example: phpIniSet 'date.timezone' 'Europe/Prague'
FIXME: reload httpd server?

=over

=back

Returns 0 if set ok.

=cut

phpIniSet () {
    [ "_$php_INI" = "_" ] && { rlLogWarning "phpIniSet: \$php_INI not defined"; return 1; }
    rlRun "rlFileBackup $php_INI"
    rlRun "sed -i '/$1/d' $php_INI"
    rlRun "echo '$1=$2' >> $php_INI"
    return 0
}

true <<'=cut'
=pod

=head2 phpVersionCompare

Compares php version number with first parameter. You can also specify operator in second parameter.
Examples:

=over

=item phpVersionCompare "5.4"

Returns 0 if version is same, 1 if php is newer or 255 if php is older

=item phpVersionCompare "5.5.5" "<="

Returns 0 if comparison is true, 1 if not

=back

=cut

phpVersionCompare () {
    if [ "$2" ]; then
        # php converts 'true' to '1' and 'false' to '0' but we need for retval in bash true=0
        return -- `php -r "print_r ((int) ! version_compare (PHP_VERSION, \"$1\", \"$2\"));"`
    else
        return -- `php -r "print_r ((int) version_compare (PHP_VERSION, \"$1\"));"`
    fi
}

true <<'=cut'
=pod

=head2 phpPdoPhpMysqlSetup

Install php-mysql on RHEL 6 because php-mysql packages could not be in
requirements because it conflicts with php-mysqlnd package.

No matter if any php collection is used or not. It also contains assert that
pdo-mysql driver is working.

=over

=back

=cut

phpPdoPhpMysqlSetup () {
        if rlIsRHEL "<7"; then
            rlRun "rlImport distribution/RpmSnapshot" 0 "php/utils: importing needed RpmSnapshot library"
            if ! rpm -q php-mysql; then
                rlRun "RpmSnapshotCreate"
                rlRun "yum install -y php-mysql"
            fi
        fi
        rlRun "php -r 'phpinfo();' 2>&1 | grep \"^pdo_mysql\"" 0 "Check presence of php-mysql(nd)"
}

true <<'=cut'
=pod

=head2 phpPdoPhpMysqlCleanup

Restore RPMs from snapshot - so it removes php-mysql (and php-pdo if needed)
already installed by Setup on RHEL 6.

=over

=back

=cut

phpPdoPhpMysqlCleanup () {
        # uninstall php-mysql on rhel-6 if it was installed during setup
        if rlIsRHEL "<7"; then
            if [ -n "$RPM_SNAPSHOT" ]; then
                rlRun "RpmSnapshotRevert"
                rlRun "RpmSnapshotDiscard"
            fi
        fi
}


phpLibraryLoaded () {
    # needed to get variables below;
    # tests importing this lib may import httpd/http too -
    # libs are imported no more than once even when calling import multiple times
    rlRun "rlImport httpd/http" 0 "php/utils: importing needed httpd library"

    # used through the code to handle both system and collection httpd servers
    httpHTTPD=${httpHTTPD:-httpd}
    httpCONFDIR=${httpCONFDIR:-/etc/httpd}

    rlLog "php/utils: loaded using '$httpHTTPD' web server for mod_php"

    return 0
}
