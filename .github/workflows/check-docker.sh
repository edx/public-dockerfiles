#!/bin/bash
# Check Docker images for warnings and syntax errors.
set -eu -o pipefail

# Paths to Dockerfiles that haven't yet had warnings and errors dealt with. Once
# your Dockerfile builds without warnings, remove it from this list.
function is_amnesty_path {
    grep -F -q -x "$1" <<EOF
./dockerfiles/commerce-coordinator.Dockerfile
./dockerfiles/course-discovery.Dockerfile
./dockerfiles/credentials.Dockerfile
./dockerfiles/ecommerce.Dockerfile
./dockerfiles/edx-analytics-dashboard.Dockerfile
./dockerfiles/edx-analytics-data-api.Dockerfile
./dockerfiles/edx-exams.Dockerfile
./dockerfiles/edx-notes-api.Dockerfile
./dockerfiles/edx-platform.Dockerfile
./dockerfiles/enterprise-access.Dockerfile
./dockerfiles/enterprise-catalog.Dockerfile
./dockerfiles/enterprise-subsidy.Dockerfile
./dockerfiles/license-manager.Dockerfile
./dockerfiles/portal-designer.Dockerfile
./dockerfiles/program-intent-engagement.Dockerfile
./dockerfiles/registrar.Dockerfile
./dockerfiles/xqueue.Dockerfile
EOF
}


find . -name '*Dockerfile' | while IFS= read -r path; do
    if is_amnesty_path "$path"; then
        echo "Skipping $path"
    else
        echo "Checking $path"
        docker build --check --quiet -f "$path" .
    fi
    echo "======================================================================"
done
