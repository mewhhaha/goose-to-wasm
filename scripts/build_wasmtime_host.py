#!/usr/bin/env python3
"""Build the optional native host against the pinned official Wasmtime SDK."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cxx', default='clang++')
    parser.add_argument('--output', type=Path, default=ROOT/'build/bin/goose-wasmtime')
    parser.add_argument('--linkage', choices=['sdk-static', 'python-shared'], default='sdk-static')
    args = parser.parse_args()
    pin_path = ROOT/'host/wasmtime-sdk.json'
    pin = json.loads(pin_path.read_text())
    expected = json.loads((ROOT/'toolchain.json').read_text())['wasmtime_python']
    version = pin['version']
    if version != expected:
        parser.error('Wasmtime SDK and toolchain versions differ')
    if args.linkage == 'python-shared' and importlib.metadata.version('wasmtime') != expected:
        parser.error('install the pinned Wasmtime bindings: python -m pip install -r requirements.txt')
    target = platform.system().lower()+'-'+platform.machine().lower()
    if target not in pin['targets']:
        parser.error('native host SDK is not pinned for '+target)
    archive_pin = pin['targets'][target]
    directory = ROOT/'build/wasmtime-host'
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory/archive_pin['asset']
    if not archive.exists():
        url = 'https://github.com/bytecodealliance/wasmtime/releases/download/v'+version+'/'+archive.name
        temporary = archive.with_suffix('.download')
        try:
            with urllib.request.urlopen(url, timeout=60) as response, temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            if digest(temporary) != archive_pin['sha256']:
                raise RuntimeError('Wasmtime SDK download hash mismatch')
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if digest(archive) != archive_pin['sha256']:
        raise RuntimeError('Wasmtime SDK archive hash mismatch: '+str(archive))
    sdk = directory/archive.name.removesuffix('.tar.xz')
    # Copy only regular pinned members; never extract links or archive paths directly.
    with tarfile.open(archive) as package:
        prefix = sdk.name+'/include/'
        library_member = sdk.name+'/lib/libwasmtime.a'
        found_library = False
        for member in package.getmembers():
            wanted = member.name.startswith(prefix)
            if args.linkage == 'sdk-static' and member.name == library_member and member.isfile():
                wanted = True
                found_library = True
            if not wanted or not member.isfile():
                continue
            destination = (directory/member.name).resolve()
            if directory.resolve() not in destination.parents:
                raise RuntimeError('unexpected SDK header path')
            data = package.extractfile(member).read()
            if not destination.exists() or destination.read_bytes() != data:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
        if args.linkage == 'sdk-static' and not found_library:
            raise RuntimeError('pinned SDK archive lacks lib/libwasmtime.a')
    library = sdk/'lib/libwasmtime.a'
    if args.linkage == 'python-shared':
        import wasmtime._ffi as ffi
        library = Path(ffi.dll._name).resolve()
    source = ROOT/'host/wasmtime.cpp'
    compiler = shutil.which(args.cxx)
    if not compiler:
        parser.error('C++ compiler unavailable: '+args.cxx)
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    inputs = [source, pin_path, ROOT/'toolchain.json', Path(__file__).resolve(), archive,
              library, Path(compiler).resolve()]
    inputs += sorted((sdk/'include').rglob('*.h'))
    command = [compiler, '-std=c++20', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(sdk/'include'),
               str(source), str(library)]
    if args.linkage == 'sdk-static':
        command += ['-Wl,--gc-sections', '-static-libstdc++', '-static-libgcc', '-lpthread', '-ldl', '-lm']
        for name in ['libstdc++.a', 'libgcc.a', 'libgcc_eh.a']:
            path = Path(subprocess.check_output([compiler, '-print-file-name='+name], text=True).strip()).resolve()
            if not path.is_file():
                parser.error('static C++ runtime archive unavailable: '+name+'; use --linkage python-shared')
            inputs.append(path)
    else:
        command += ['-Wl,-rpath,'+str(library.parent)]
    command += ['-o', str(output)]
    hashes = {str(path):digest(path) for path in inputs}
    manifest = output.with_suffix('.json')
    if output.exists() and manifest.exists():
        old = json.loads(manifest.read_text())
        if old.get('input_sha256') == hashes and old.get('host_sha256') == digest(output) and old.get('command') == command:
            print('Native Wasmtime host is current:', output)
            return
    subprocess.run(command, cwd=ROOT, check=True)
    assert hashes == {str(path):digest(path) for path in inputs}
    metadata = {'schema':'goose-native-wasmtime-host-v1', 'version':version, 'target':target,
                'linkage':args.linkage, 'static_cxx_runtime':args.linkage == 'sdk-static',
                'supported_modes':['ordinary', 'cached', 'precompiled', 'worker'],
                'library':str(library),'library_sha256':digest(library),
                'sdk_archive':str(archive), 'sdk_archive_sha256':archive_pin['sha256'], 'input_sha256':hashes,
                'command':command,'host_sha256':digest(output),
                'cxx_version':subprocess.check_output([compiler,'--version'],text=True)}
    manifest.write_text(json.dumps(metadata,indent=2)+'\n')
    print('Built',output,'using',args.linkage,library)


if __name__=='__main__':
    main()
