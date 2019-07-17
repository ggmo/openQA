# Copyright (C) 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package OpenQA::Schema::Result::ScreenshotLinks;

use strict;
use warnings;

use base 'DBIx::Class::Core';

use File::Spec::Functions 'catfile';
use OpenQA::Utils qw(log_debug log_warning);
use Try::Tiny;

__PACKAGE__->table('screenshot_links');

__PACKAGE__->add_columns(
    screenshot_id => {
        data_type   => 'integer',
        is_nullable => 0,
    },
    job_id => {
        data_type   => 'integer',
        is_nullable => 0,
    });

__PACKAGE__->belongs_to(job        => 'OpenQA::Schema::Result::Jobs',        'job_id');
__PACKAGE__->belongs_to(screenshot => 'OpenQA::Schema::Result::Screenshots', 'screenshot_id');

sub _list_images_subdir {
    my ($app, $prefix, $dir) = @_;
    log_debug "reading $prefix/$dir";
    my $subdir = catfile($OpenQA::Utils::imagesdir, $prefix, $dir);
    my $dh;
    if (!opendir($dh, $subdir)) {
        log_warning "Can't open $subdir: $!";
        return;
    }
    my @ret;
    for my $file (readdir $dh) {
        my $fn = catfile($subdir, $file);
        if (-f $fn) {
            push(@ret, catfile($prefix, $dir, $file));
        }
    }
    closedir($dh);
    return \@ret,;
}

# gru task to scan XXX subdirectory
sub scan_images {
    my ($app, $args) = @_;

    return unless $args->{prefix};
    my $dh;
    my $prefixdir = catfile($OpenQA::Utils::imagesdir, $args->{prefix});
    if (!opendir($dh, $prefixdir)) {
        log_warning "Can't open $args->{prefix} in $OpenQA::Utils::imagesdir: $!";
        return;
    }
    my @files;
    my $now = DateTime->now;
    push(@files, [qw(filename t_created)]);
    for my $file (readdir $dh) {
        if ($file !~ /^\./ && -d "$prefixdir/$file") {
            push(@files, map { [$_, $now] } @{_list_images_subdir($app, $args->{prefix}, $file)});
        }
    }
    closedir($dh);
    $app->schema->resultset('Screenshots')->populate(\@files);
    return;
}

sub populate_images_to_job {
    my ($schema, $imgs, $job_id) = @_;

    # insert the symlinks into the DB
    my $data  = [[qw(screenshot_id job_id)]];
    my $dbids = $schema->resultset('Screenshots')->search({filename => {-in => $imgs}});
    my %ids;
    while (my $screenshot = $dbids->next) {
        $ids{$screenshot->filename} = $screenshot->id;
    }
    my $now = DateTime->now;
    for my $img (@$imgs) {
        next if $ids{$img};
        try {
            log_debug "creating $img";
            $ids{$img} = $schema->resultset('Screenshots')->create({filename => $img, t_created => $now})->id;
        }
        catch {
            # it's possible 2 jobs are creating the link at the same time
            $ids{$img} = $schema->resultset('Screenshots')->find({filename => $img})->id;
        };
    }
    for my $id (values %ids) {
        push(@$data, [$id, $job_id]);
    }
    $schema->resultset('ScreenshotLinks')->populate($data);
    return;
}

1;
