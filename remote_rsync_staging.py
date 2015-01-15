#!/usr/bin/env python
#-*- coding: utf-8 -*-


import datetime
import logging
import os
import re
import subprocess
import tempfile


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('rsync_staging')

now = datetime.datetime.utcnow()
staging_snapshot_stamp_format = r'%Y-%m-%d-%H%M%S'
staging_snapshot_stamp_regexp = r'[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}'
staging_snapshot_stamp = now.strftime(staging_snapshot_stamp_format)


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
        self.staging_postfix = staging_postfix
        self.staging_snapshot_stamp = staging_snapshot_stamp
        self.staging_snapshot_stamp_format = staging_snapshot_stamp_format
        if re.match(staging_snapshot_stamp_regexp,
                    self.staging_snapshot_stamp) \
                is not None:
            self.staging_snapshot_stamp_regexp = staging_snapshot_stamp_regexp
        else:
            raise RuntimeError('Wrong regexp for staging_snapshot_stamp\n'
                               'staging_snapshot_stamp = "{}"\n'
                               'staging_snapshot_stamp_regexp = "{}"'.
                               format(staging_snapshot_stamp,
                                      staging_snapshot_stamp_regexp)
                               )

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
        logger.info(cmd)
        process = subprocess.Popen(cmd,
                                   stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   shell=True)
        out, err = process.communicate()
        logger.debug(out)
        exitcode = process.returncode
        if process.returncode != 0 and raise_error:
            msg = '"{cmd}" failed. Exit code == {exitcode}'\
                  '\n\nSTDOUT: \n{out}'\
                  '\n\nSTDERR: \n{err}'\
                  .format(**(locals()))
            logger.error(msg)
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
            self._remove_old_snapshots()
            return exitcode, out, err
        except RuntimeError as e:
            logger.error(e.message)
            self.rsync_delete_dir(self.staging_dir_path)
            raise

    def _remove_old_snapshots(self, save_last_days=None):
        if save_last_days is None:
            save_last_days = self.save_last_days
        if save_last_days is None \
                or save_last_days is False \
                or save_last_days == 0:
            # skipping deletion if save_last_days == None or False or 0
            logger.info('Skip deletion of old snapshots because of '
                        'save_last_days == {}'.format(save_last_days))
            return
        warn_date = now - datetime.timedelta(days=save_last_days)
        warn_date = datetime.datetime.combine(warn_date, datetime.time(0))
        dirs = self.rsync_ls_dirs(
            '{}/'.format(self.files_path),
            pattern='^{}-{}'.format(self.mirror_name,
                                    self.staging_snapshot_stamp_regexp)
        )[1]
        links = self.rsync_ls_symlinks('{}/'.format(self.root_path))[1]
        links += self.rsync_ls_symlinks('{}/'.format(self.files_path))[1]
        for d in dirs:
            dir_date = datetime.datetime.strptime(
                d,
                '{}-{}'.format(self.mirror_name,
                               self.staging_snapshot_stamp_format)
            )
            dir_date = datetime.datetime.combine(dir_date, datetime.time(0))
            dir_path = '{}/{}'.format(self.files_path, d)
            if dir_date < warn_date:
                dir_links = [_[0] for _ in links
                             if _[1] == d
                             or _[1].endswith('/{}'.format(d))
                             ]
                if not dir_links:
                    self.rsync_delete_dir(dir_path)
                else:
                    logger.info('Skip deletion of "{}" because there are '
                                'symlinks found: {}'.format(d, dir_links))
