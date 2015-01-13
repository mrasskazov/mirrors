#!/usr/bin/env python
#-*- coding: utf-8 -*-


import datetime
import os
import re
import subprocess
import tempfile


now = datetime.datetime.now()
staging_snapshot_stamp = \
    '{:04}-{:02}-{:02}-{:02}{:02}{:02}'.format(
        now.year, now.month, now.day, now.hour, now.minute, now.second)


class RemoteRsyncStaging(object):
    def __init__(self,
                 mirror_name,
                 host,
                 user='mirror-sync',
                 root_path='fwm',
                 files_dir='files',
                 save_last_days=61,
                 rsync_extra_params='-v',
                 staging_postfix='staging'):
        self.mirror_name = mirror_name
        self.host = host
        self.user = user
        self.root_path = root_path
        self.files_dir = files_dir
        self.save_last_days = save_last_days
        self.rsync_extra_params = rsync_extra_params
        self.staging_snapshot_stamp = staging_snapshot_stamp
        self.staging_postfix = staging_postfix

    @property
    def url(self):
        return '{}::{}'.format(self.host, self.user)

    @property
    def root_url(self):
        return '{}/{}'.format(self.url, self.root_path)

    @property
    def files_path(self):
        return '{}/{}'.format(self.root_path, self.files_dir)

    @property
    def files_url(self):
        return '{}/{}'.format(self.root_url, self.files_dir)

    def http_url(self, path):
        return 'http://{}/{}'.format(self.host, path)

    def html_link(self, path, link_name):
        return '<a href="{}">{}</a>'.format(self.http_url(path), link_name)

    @property
    def staging_dir(self):
        return '{}-{}'.format(self.mirror_name, self.staging_snapshot_stamp)

    @property
    def staging_dir_path(self):
        return '{}/{}'.format(self.files_path, self.staging_dir)

    @property
    def staging_dir_url(self):
        return '{}/{}'.format(self.url, self.staging_dir_path)

    @property
    def staging_link(self):
        return '{}-{}'.format(self.mirror_name, self.staging_postfix)

    @property
    def staging_link_path(self):
        return '{}/{}'.format(self.files_path, self.staging_link)

    @property
    def staging_link_url(self):
        return '{}/{}'.format(self.url, self.staging_link_path)

    @property
    def empty_dir(self):
        if self.__dict__.get('_empty_dir') is None:
            self._empty_dir = tempfile.mkdtemp()
        return self._empty_dir

    def symlink_to(self, target):
        linkname = tempfile.mktemp()
        os.symlink(target, linkname)
        return linkname

    def _shell(self, cmd, raise_error=True):
        print cmd
        process = subprocess.Popen(cmd,
                                   stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   shell=True)
        out, err = process.communicate()
        exitcode = process.returncode
        if process.returncode != 0 and raise_error:
            msg = '"{cmd}" failed. Exit code == {exitcode}'\
                  '\n\nSTDOUT: \n{out}'\
                  '\n\nSTDERR: \n{err}'\
                  .format(**(locals()))
            raise RuntimeError(msg)
        return exitcode, out, err

    def _do_rsync(self, source='', dest=None, opts='', extra=None):
        if extra is None:
            extra = self.rsync_extra_params
        cmd = 'rsync {opts} {extra} {source} {dest}'.format(**(locals()))
        return self._shell(cmd)

    def _rsync_ls(self, dirname=None, pattern=r'.*', opts=''):
        if dirname is None:
            dirname = '{}/'.format(self.root_path)
        dest = '{}/{}'.format(self.url, dirname)
        extra = self.rsync_extra_params + ' --no-v'
        exitcode, out, err = self._do_rsync(dest=dest, opts=opts, extra=extra)
        regexp = re.compile(pattern)
        out = [_ for _ in out.splitlines()
               if (_.split()[-1] != '.') and
               (regexp.match(_.split()[-1]) is not None)]
        return exitcode, out, err

    def rsync_ls(self, dirname, pattern=r'.*'):
        exitcode, out, err = self._rsync_ls(dirname, pattern=pattern)
        out = [_.split()[-1] for _ in out]
        return exitcode, out, err

    def rsync_ls_dirs(self, dirname, pattern=r'.*'):
        exitcode, out, err = self._rsync_ls(dirname, pattern=pattern)
        out = [_.split()[-1] for _ in out if _.startswith('d')]
        return exitcode, out, err

    def rsync_ls_symlinks(self, dirname, pattern=r'.*'):
        exitcode, out, err = self._rsync_ls(dirname,
                                            pattern=pattern,
                                            opts='-l')
        out = [_.split()[-3:] for _ in out if _.startswith('l')]
        out = [[_[0], _[-1]] for _ in out]
        return exitcode, out, err

    def rsync_delete_file(self, filename):
        dirname, filename = os.path.split(filename)
        source = '{}/'.format(self.empty_dir)
        dest = '{}/{}/'.format(self.url, dirname)
        opts = "-r --delete --include={} '--exclude=*'".format(filename)
        return self._do_rsync(source=source, dest=dest, opts=opts)

    def rsync_delete_dir(self, dirname):
        source = '{}/'.format(self.empty_dir)
        dest = '{}/{}/'.format(self.url, dirname)
        opts = "-a --delete"
        exitcode, out, err = self._do_rsync(source=source,
                                            dest=dest,
                                            opts=opts)
        return self.rsync_delete_file(dirname)

    def rsync_staging_transfer(self, source, tgt_symlink_name=None):
        if tgt_symlink_name is None:
            tgt_symlink_name = self.mirror_name
        opts = '--archive --force --ignore-errors '\
               '--delete-excluded --no-owner --no-group --delete '\
               '--link-dest=/{}'.format(self.staging_link_path)
        try:
            exitcode, out, err = self._do_rsync(source=source,
                                                dest=self.staging_dir_url,
                                                opts=opts)
            self.rsync_delete_file(self.staging_link_path)
            self._do_rsync(source=self.symlink_to(self.staging_dir),
                           dest=self.staging_link_url,
                           opts='-l')
            # cleaning of old snapshots
            return exitcode, out, err
        except RuntimeError as e:
            print e.message
            self.rsync_delete_dir(self.staging_dir_path)
            raise
