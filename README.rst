Dockerfiles and image publish workflows
#######################################

Base dockerfiles for edX services. These files are used in two ways:

- Devstack: GH workflows in this repo build the images and upload them to a public docker repository, for use in devstack.
- Deployments: GoCD pipelines build these images and upload to a *private* repository, then build on top of them with the dockerfiles in <https://github.com/edx/internal-dockerfiles>, producing the images actually used in deployments.

Locally build the images
************************

We can locally build and test the images. Following steps are to be taken to test the images.

1. Clone the repository into ``~/{WORKSPACE}/``
2. Navigate to your repository by using ``cd ~/{WORKSPACE}/{REPO}/``
2. Build the image using following command: ``docker build -t <image-name>:<tag> --target <target> -f <path-to-your-dockerfile> . --progress=plain`` (or you can go with your custom tag for testing)
   i. For example, to build edx-platform cms, you can use the following command: ``docker build -t edx-platform:dev --target development -f ~/{WORKSPACE}/public-dockerfiles/dockerfiles/edx-platform.Dockerfile ~/{WORKSPACE}/edx-platform --build-arg=SERVICE_VARIANT="cms" --build-arg=SERVICE_PORT="18010" --progress=plain``
3. Once the image is built, you can inspect the image with a shell by running ``docker run -it --rm <image-name>:<tag> bash -c "/bin/bash"``
4. To run the container for the image, you must use devstack. Please see `docs for setting up Colima for devstack`_.

.. _docs for setting up Colima for devstack: https://2u-internal.atlassian.net/wiki/spaces/ENG/pages/894140516/Setting+up+Colima+for+devstack

Building images with BuildKit (Mac only)
****************************************
For Macs, the dockerfiles in public-dockerfiles may be built with buildx/BuildKit, the new docker build system.
Please see `docs for setting up Colima for devstack`_ for instructions to build with Buildkit.

Authoring
*********

See ``docs/dockerfile-tips.rst`` for additional information on writing Dockerfiles for 2U's infrastructure, environment, and standards.

Handling image publish failures
*******************************

In case you receive an email informing you regarding failure to publish the image, please refer to `this document <https://2u-internal.atlassian.net/wiki/spaces/AT/pages/1648787501/Runbook+for+handling+failure+to+publish+docker+image>`__.

How to Contribute
*****************

If you wish to contribute to the repository either optimizing workflows or updating dockerfiles, please create an issue against the work you want to take up. Once tested image locally, raise a PR and request review from `orbi-bom team <https://github.com/orgs/edx/teams/orbi-bom>`__. If you are changing dockerfiles of any particular IDA, it's advisable to get a review from the owner team as well. IDAs ownership and team info can be found at `this sheet <https://docs.google.com/spreadsheets/d/1qpWfbPYLSaE_deaumWSEZfz91CshWd3v3B7xhOk5M4U/view?gid=1990273504#gid=1990273504>`__.
