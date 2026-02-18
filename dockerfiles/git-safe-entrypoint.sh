#!/usr/bin/env bash
# Entrypoint script to configure git safe.directory for the current user
# This handles cases where containers run with different UIDs in Kubernetes
set -e

# Only configure git if it's available
if command -v git >/dev/null 2>&1; then
    # Get the list of directories that might be git repositories
    # This script assumes standard edX directory layouts
    
    # Common patterns for edX services
    GIT_DIRS=(
        "/edx/app/edxapp/edx-platform"
        "/edx/app/discovery/discovery"
        "/edx/app/ecommerce/ecommerce"
        "/edx/app/xqueue/xqueue"
        "/edx/app/credentials/credentials"
        "/edx/app/enterprise-subsidy"
        "/edx/app/enterprise-catalog/enterprise-catalog"
        "/edx/app/enterprise-access/enterprise-access"
        "/edx/app/commerce-coordinator/commerce-coordinator"
        "/edx/app/edx-exams/edx-exams"
        "/edx/app/edx-notes-api/edx-notes-api"
        "/edx/app/analytics_dashboard/analytics_dashboard"
        "/edx/app/analytics_api/analytics_api"
        "/edx/app/license-manager/license-manager"
        "/edx/app/portal-designer/portal-designer"
        "/edx/app/program-intent-engagement/program-intent-engagement"
        "/edx/app/registrar/registrar"
    )
    
    # Add each directory as safe if it exists
    for dir in "${GIT_DIRS[@]}"; do
        if [ -d "$dir/.git" ]; then
            git config --global --add safe.directory "$dir" || true
        fi
    done
fi

# Execute the original command
exec "$@"
