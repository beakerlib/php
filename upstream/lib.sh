#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /CoreOS/php/Library/upstream
#   Description: Library for running and evaluating upstream tests
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
#   library-prefix = phpUp_
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

php/upstream

=head1 DESCRIPTION

Library for running and evaluating upstream tests

PLAN (in czech only for now, sorry):

 - knihovna ke spousteni php upstream testu:
  > - spusteni adresare (idelalne/volitelne celeho podstromu)
      - one test - one assert
      - one leaf dir - one phase -- probably NOT:
        - phases are not tree
        - want to have other aserts in phase ?
    - spusteni konkretniho testu
    - ulozeni vysledku do archivu
    - porovnani vysledku ze dvou archivu

    - uklada srpm do sveho adresare
      - pokud tam uz je, nestahuje
    - instaluje srpm
      - pokud uz je instalovano ne?
    - rpmbuild -bp
      - pokud je to z minula nedelat? jak to zjistit?

=cut


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 phpUp_RunTestDir

Runs all the tests present in given subdirectory of php upstream tarball

    phpUp_RunTestDir php subdir recursive results

=over

=item php

php full package name to use - binary one, eg. from phpMainPackage()

=item subdir

subdirectory of upstream tarball, eg. ext/mysql/tests

=item recursive

whether to run all the tests in whole subdir tree recursively; do not by default (0/1) - FIXME: TODO

=item results

filename where to store tarball with results; use test dir by default (testdir/$php-results.tgz)

=back

Returns 0 when everything is ok, 1 otherwise. Also asserts.
Detailed results are tared into results if provided.

=cut

phpUp_RunTestDir() {
    [ $# -lt 2 ] && { rlFail "phpUp_RunTestDir needs at least 2 parameters!"; return 1; }

    local php="$1"
    local subdir="$2"
    local recursive="${3:-0}"
    local results="${4:-/tmp/phpUp_RunTestDir-last-result.tgz}"  # FIXME: better default results dir

    local version=`rpm -q $php --qf '%{VERSION}'`
    local release=`rpm -q $php --qf '%{RELEASE}'`
    local nvr=`rpm -q $php --qf '%{N}-%{V}-%{R}'`
    local arch=`arch`
    [ _$arch = _i686 ] && arch=i386

    local builddir="`rpm --eval '%_builddir'`"
    local pkgbuild="${builddir}/php-$version"
    local specdir=`rpm --eval '%_specdir'`

    # download src.rpm if needed
    if [ ! -r "$phpUp_PackageDir/$nvr.src.rpm" ]; then
        rlRun "rlFetchSrcForInstalled '$nvr'"
        mv "./$nvr.src.rpm" "$phpUp_PackageDir/"
    else
        rlLog "src rpm already downloaded: $phpUp_PackageDir/$nvr.src.rpm"
    fi
    ls -l "$phpUp_PackageDir/$nvr.src.rpm"

    # install it
    rlRun "rpm -Uvh $phpUp_PackageDir/$nvr.src.rpm"

    # install builddeps
    rlRun "yum-builddep -y $phpUp_PackageDir/$nvr.src.rpm"

    # prepare it (patches etc: -bp)
    local phpspec="$(echo $specdir/php*.spec)"
    rlRun "rpmbuild -bp '$phpspec'"
    rlLog "builddir='$builddir' pkgbuild='$pkgbuild'"
    local php_tmp=$(mktemp -d)
    pushd "$php_tmp"
    rlRun "cp -R $pkgbuild ./"

    # are we ready and working till now?
    export NO_INTERACTION=1 REPORT_EXIT_STATUS=1 MALLOC_CHECK_=2 TEST_PHP_EXECUTABLE=$(which php)
    rlLog "phpUp_RunTest: using $TEST_PHP_EXECUTABLE"

    cd ./*

    php ./run-tests.php --help
    rlRun "php -d 'memory_limit=-1' -d 'output_buffering=0' ./run-tests.php -w ../failed-and-warned.txt -s ../summary.txt $subdir 2>&1 | tee ../run-tests.out.txt"

    # create asserts from individual results
    # possible php values: PASS, FAIL, XFAIL, SKIP, BORK, WARN, LEAK, REDIRECT

    cat ../run-tests.out.txt | tr '\r' ':' | grep '\(PASS\|FAIL\|XFAIL\|SKIP\|BORK\|WARN\|LEAK\|REDIRECT\) ' | sed 's/^[^:]*:\([A-Z]*\).*\[\(.*\)\].*/\1:\2/' > ../results.txt

    local line
    local state
    local testname
    while read line; do
        state=$(echo $line | sed 's/:.*$//')
        testname=$(echo $line | sed 's/^.*://')
        case $state in
            'PASS') rlPass "$testname"
                ;;
            'XFAIL') rlPass "(XFAIL) $testname"
                ;;
            'SKIP') rlLog "(SKIP) $testname"
                ;;
            'REDIRECT') rlLog "(REDIRECT) $testname"
                ;;
            'WARN') rlLog " (WARN) $testname"
                ;;
            'LEAK') rlFail "(LEAK) $testname"
                ;;
            'FAIL') rlFail "$testname"
                ;;
            'BORK') rlFail "(BORK) $testname"
                ;;
            *) rlLogError "Unknown test result state: $state"
                ;;
        esac

    done < ../results.txt

    # ^ asserts done

    # and our results...
    find $subdir -name '*.php' -o -name '*.out' -o -name '*.exp' -o -name '*.log' -o -name '*.phpt' -o -name '*.diff' > result-files.txt
    echo ../*.txt >> result-files.txt
    tar cvf $results -T result-files.txt

    popd
    rm -r "$php_tmp"
}


phpUp_LibraryLoaded () {

    phpUp_PackageDir="/tmp" # FIXME

    # there is no action / initialization with library import
    # we could check for php bin or mod_php, but
    # that is what a test will do anyway as needs via provided functions
    # so lets say ok all the time
    return 0
}
