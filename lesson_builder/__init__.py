from . import build, github, config

__author__ = 'Justus Adam'
__version__ = '0.1'


def _main():
    """Main function"""
    import sys
    script, wd, *l = sys.argv
    print(build.build_and_report(wd))

if __name__ == '__main__':
    _main()
else:
    del _main