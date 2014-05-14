#!/usr/bin/env python
#-*- coding: utf-8 -*-

from datetime import datetime
import os


tpl_head = '''<html>
<head><title>Index of {curdir}</title></head>
<body bgcolor="white">
<h1>Index of {curdir}</h1><hr><pre><a href="../">../</a>'''

tpl_file = '<a href="{target}">{dispname}</a>{sep}{datetime:<17} {size:>19}'
tpl_link = tpl_file + ' =&gt <a href="{ln_target}">{ln_target}</a>'

tpl_foot = '''</pre><hr></body>
</html>
'''


def main():

    server_root = '/media/mirrors/mirrors'
    #curdir = os.path.realpath('.').replace(os.getcwd(), '/')
    curdir = os.path.realpath('.').replace(server_root, '')
    curdir = '/' if not curdir else curdir

    print tpl_head.format(curdir=curdir)

    for f in sorted(os.listdir('.')):
        if f == 'index.html' or f == 'dirlist.py':
            continue
        v = {
            'target': f,
            'dispname': f,
            'sep': ' ' * (51 - len(f)),
            'datetime': datetime.fromtimestamp(
                os.path.getctime(f)).strftime('%d-%b-%Y %H:%M'),
            'size': os.path.getsize(f),
        }

        if os.path.isdir(f):
            v['target'] += '/'
            v['dispname'] += '/'
            v['sep'] = v['sep'][:-1]

        if os.path.isdir(f) or os.path.islink(f):
            v['size'] = '-'

        if os.path.islink(f):
            v['ln_target'] = os.path.realpath(f).replace(os.getcwd() +
                                                         os.path.sep, '')
            print tpl_link.format(**v)
        else:
            print tpl_file.format(**v)

    print tpl_foot

    return 0


if __name__ == '__main__':
    main()
