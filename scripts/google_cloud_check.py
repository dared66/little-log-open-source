#!/usr/bin/env python3
"""Read the production project's identity and enabled APIs using an existing gcloud login."""
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_APIS = {'drive.googleapis.com', 'picker.googleapis.com'}


def check():
    if not shutil.which('gcloud'):
        raise RuntimeError('Install the official Google Cloud CLI first.')
    config = json.loads((ROOT / 'config/google.production.json').read_text())
    project = config['GOOGLE_CLOUD_PROJECT_ID']

    def read(*args):
        result = subprocess.run(
            ['gcloud', *args, f'--project={project}', '--quiet', '--format=json'],
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or 'Google Cloud read failed.')
        return json.loads(result.stdout)

    identity = read('projects', 'describe', project)
    if (identity.get('projectId') != project
            or str(identity.get('projectNumber')) != config['GOOGLE_PROJECT_NUMBER']
            or identity.get('lifecycleState') != 'ACTIVE'):
        raise RuntimeError('Production project identity or lifecycle does not match.')
    services = read('services', 'list', '--enabled')
    enabled = {service['config']['name'] for service in services}
    missing = REQUIRED_APIS - enabled
    if missing:
        raise RuntimeError('Missing production APIs: ' + ', '.join(sorted(missing)))
    print(f"Verified {project} ({config['GOOGLE_PROJECT_NUMBER']}): Drive and Picker enabled.")
    print('OAuth publication, branding and native client details are checked in Google Auth Platform.')


if __name__ == '__main__':
    try:
        check()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f'Google Cloud check failed: {exc}', file=sys.stderr)
        sys.exit(1)
