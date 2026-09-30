"""Check both consumers' pinned local dependency refresh without any network access."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile


def git(directory, *args):
    return subprocess.check_output(['git', '-C', str(directory), *args], text=True).strip()


def commit(directory, message):
    git(directory, 'add', '.')
    git(directory, '-c', 'user.name=Dependency Check', '-c', 'user.email=check@example.invalid',
        'commit', '-qm', message)
    return git(directory, 'rev-parse', 'HEAD')


def refresh(script, source, destination, outer, core, managed='true'):
    env = {**os.environ, 'FDAPDE_CPP_COMMIT': outer, 'FDAPDE_CORE_COMMIT': core,
           'FDAPDE_CPP_MANAGED': managed, 'FDAPDE_CORE_REPOSITORY': ''}
    return subprocess.run(['bash', str(script), str(source), 'codex/unpublished', str(destination)],
                          env=env, text=True, capture_output=True, timeout=30)


def check(script, work):
    core_source = work / 'core-source'
    source = work / 'source'
    destination = work / 'prepared'
    for directory in (core_source, source):
        directory.mkdir()
        git(directory, 'init', '-q')
    (core_source / 'core.h').write_text('// local core fixture\n')
    core = commit(core_source, 'Local core')
    (source / 'fdaPDE').mkdir()
    (source / 'fdaPDE/models.h').write_text('// local model fixture\n')
    git(source, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(core_source), 'fdaPDE/core')
    first = commit(source, 'Local model')
    git(source, 'switch', '-qc', 'codex/unpublished')
    (source / 'fdaPDE/models.h').write_text('// new local model fixture\n')
    second = commit(source, 'Unpublished model')
    result = refresh(script, source, destination, first, core)
    # a pin selects the old local commit even when the unpublished branch has moved
    assert result.returncode == 0 and git(destination, 'rev-parse', 'HEAD') == first, result.stderr
    # the prepared submodule must use exactly the outer gitlink
    assert git(destination / 'fdaPDE/core', 'rev-parse', 'HEAD') == core
    result = refresh(script, source, destination, second, core)
    # refresh must make an unpublished local commit available without a remote branch
    assert result.returncode == 0 and git(destination, 'rev-parse', 'HEAD') == second, result.stderr
    result = refresh(script, source, destination, first, '0' * 40)
    # a mismatched core pin must be rejected before changing the outer checkout
    assert result.returncode != 0 and git(destination, 'rev-parse', 'HEAD') == second
    result = refresh(script, source, destination, second, core, 'false')
    # unmanaged validation of the exact pair must succeed without a checkout
    assert result.returncode == 0, result.stderr
    result = refresh(script, source, destination, first, core, 'false')
    # unmanaged validation must reject a different outer commit without altering the checkout
    assert result.returncode != 0 and git(destination, 'rev-parse', 'HEAD') == second
    model_header = destination / 'fdaPDE/models.h'
    model_header.write_text('// user edit\n')
    result = refresh(script, source, destination, first, core)
    # managed refresh must preserve dirty outer files and the current commit
    assert result.returncode != 0 and model_header.read_text() == '// user edit\n'
    git(destination, 'restore', 'fdaPDE/models.h')
    core_header = destination / 'fdaPDE/core/core.h'
    core_header.write_text('// user core edit\n')
    result = refresh(script, source, destination, first, core)
    # managed refresh must also preserve dirty submodule files
    assert result.returncode != 0 and core_header.read_text() == '// user core edit\n'
    print(f'OK {script}: unpublished pins, refresh, unmanaged validation and dirty checkout preservation')


def main():
    simulation = Path(__file__).resolve().parents[1]
    scripts = [Path(arg).resolve() for arg in sys.argv[1:]] or [
        simulation / 'cpp/clone_fdapde.sh', simulation.parent / 'fPLS-application/cpp/clone_fdapde.sh']
    with tempfile.TemporaryDirectory(prefix='fdapde-dependency-check-') as temporary:
        for index, script in enumerate(scripts):
            work = Path(temporary) / str(index)
            work.mkdir()
            check(script, work)


if __name__ == '__main__':
    main()
