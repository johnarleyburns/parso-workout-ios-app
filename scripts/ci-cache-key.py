#!/usr/bin/env python3
"""Version compiled caches by toolchain, platform, scope and package inputs."""
import hashlib
import os
from pathlib import Path
import platform
import subprocess
import sys


def identity(*, scope, system, arch, toolchain, inputs, sha):
    if scope not in ('host', 'device', 'archive'):
        raise ValueError('cache scope must be host, device or archive')
    tool_hash = hashlib.sha256(toolchain.encode()).hexdigest()[:16]
    input_hash = hashlib.sha256(inputs).hexdigest()[:16]
    prefix = f'cadence-build-v1-{system}-{arch}-{tool_hash}-{scope}-{input_hash}-'
    return {'prefix': prefix, 'key': prefix + sha}


def main():
    scope = sys.argv[1]
    root = Path(__file__).resolve().parents[1]
    files = ['CadenceCore/Package.swift', 'CadenceCore/Package.resolved',
             'Cadence/Cadence.xcodeproj/project.pbxproj',
             'scripts/ci-validate.sh', 'scripts/xcodebuild-safe.sh']
    inputs = b''.join(name.encode() + b'\0' + (root / name).read_bytes() + b'\0' for name in files)
    toolchain = '\n'.join(subprocess.check_output(command, text=True) for command in
                          (['xcodebuild', '-version'], ['swift', '--version']))
    values = identity(scope=scope, system=platform.system(), arch=platform.machine(),
                      toolchain=toolchain, inputs=inputs, sha=os.environ['GITHUB_SHA'])
    for key, value in values.items():
        print(f'{key}={value}')
    print(f'derived-data={root}/.build/ci-derived-{scope}')
    print(f'source-packages={root}/.build/ci-source-packages')


if __name__ == '__main__':
    main()
