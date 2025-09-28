#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME               => 'Role',
    AUTHOR             => q{Mohammad Sajid Anwar <mohammad.anwar@yahoo.com>},
    VERSION_FROM       => 'lib/Role.pm',
    ABSTRACT_FROM      => 'lib/Role.pm',
    LICENSE            => 'artistic_2',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    PREREQ_PM => {
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    test  => { TESTS => 't/*.t' },
    clean => { FILES => 'Role-*' },
    (eval { ExtUtils::MakeMaker->VERSION(6.46) } ? (META_MERGE => {
        'meta-spec' => { version => 2 },
        provides    => { 'Role'  => { file => 'lib/Role.pm', version => '0.02' } },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/manwar/Role.git',
                web  => 'https://github.com/manwar/Role',
            },
        }})
     : ()
    ),
);
