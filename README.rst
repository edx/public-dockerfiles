Dockerfiles and image publish workflows
#######################################

Under the `epic <https://github.com/edx/public-dockerfiles/issues/12>`__ to remove dockerfiles and workflow setup for devstack, dockerfiles were moved to this repository.

Overview
********

This repository aims to streamline all the dockerfiles and docker images publishing from a single source. Images for the following services are included in this repo.

- commerce-coordinator
- codejail-service
- course-discovery
- credentials
- ecommerce
- edx-analytics-dashboard
- edx-analytics-data-api
- edx-exams
- edx-notes-api
- edx-platform
- enterprise-access
- enterprise-subsidy
- enterprise-catalog
- license-manager
- portal-designer
- program-intent-engagement
- registrar
- xqueue

Locally build the images
************************

We can locally build and test the images. Following steps are to be taken to test the images.

1. Clone the repository into ``~/{WORKSPACE}/``
2. Navigate to your repository by using ``cd ~/{WORKSPACE}/{REPO}/``
2. Build the image using following command: ``docker build -t <image-name>:<tag> --target <target> -f <path-to-your-dockerfile> . --progress=plain`` (or you can go with your custom tag for testing)
   i. For example, to build edx-platform cms, you can use the following command: ``docker build -t edx-platform:dev --target development -f ~/{WORKSPACE}/public-dockerfiles/dockerfiles/edx-platform.Dockerfile ~/{WORKSPACE}/edx-platform --build-arg=SERVICE_VARIANT="cms" --build-arg=SERVICE_PORT="18010" --progress=plain``
3. Once the image is built, you can run the container for that image using the following command: ``docker container run --name <name-for-container> <name-of-image-built>``
   i. For example, to run the edx-platform image built in previous step, you can use the following command: ``docker container run --name edx-platform-dev edx-platform:dev`` 
4. Once the container runs, you can enter the shell using this command: ``docker exec -it <container-name> <shell-executable>``
   i. For example, to enter the shell of edx-platform container, you can use the following command: ``docker exec -it edx-platform-dev /bin/bash``
5. You can run commands in shell and test if the image is is built correctly and container is running smoothly.

Building images with BuildKit
*****************************
The dockerfiles in public-dockerfiles may require to be built with buildx/BuildKit, the new docker build system.

1. run ``brew install docker-buildx``
2. Make sure buildx is available for the local user
   a. ``mkdir -p ~/.docker/cli-plugins``
   b. ``ln -sfn /opt/homebrew/opt/docker-buildx/bin/docker-buildx ~/.docker/cli-plugins/docker-buildx``
3. To run docker build with buildkit, use the buildx command-
   a. Navigate to the folder with the ``edx-platform.Dockerfile``
   b. ``docker buildx build -f edx-platform.Dockerfile …``

Authoring
*********

See ``docs/dockerfile-tips.rst`` for additional information on writing Dockerfiles for 2U's infrastructure, environment, and standards.

Repository Structure
********************

.. code:: plaintext

   ├── dockerfiles/
   │   ├── ida1.Dockerfile
   │   ├── ida2.Dockerfile
   │   ├── ...
   │   └── idaN.Dockerfile
   ├── workflows/
   │   └── push-docker-images.yml
   ├── README.md
   └── .gitignore

Handling image publish failures
*******************************

In case you receive an email informing you regarding failure to publish the image, please refer to `this document <https://2u-internal.atlassian.net/wiki/spaces/AT/pages/1648787501/Runbook+for+handling+failure+to+publish+docker+image>`__.

How to Contribute
*****************

If you wish to contribute to the repository either optimizing workflows or updating dockerfiles, please create an issue against the work you want to take up. Once tested image locally, raise a PR and request review from `arbi-bom team <https://github.com/orgs/openedx/teams/2u-arbi-bom>`__. If you are changing dockerfiles of any particular IDA, it's advisable to get a review from the owner team as well. IDAs ownership and team info can be found at `this sheet <https://docs.google.com/spreadsheets/d/1qpWfbPYLSaE_deaumWSEZfz91CshWd3v3B7xhOk5M4U/view?gid=1990273504#gid=1990273504>`__.
