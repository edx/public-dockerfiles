Dockerfile tips
###############

App user
********

The django-ida helm chart always runs the application as user ID 1000. For Ubuntu images up through Jammy (22.04), this will be the first user that was created in the Dockerfile. However, in Noble (24.04), the image already contains an ``ubuntu`` user with that ID.

Dockerfiles that want to use a custom user (often named ``app``) in 24.04 and later will need to first delete the ``ubuntu`` user. Here's a snippet you can include::

  # Remove the `ubuntu` user so that UID 1000 is freed up for creating an app
  # user. This is specific to 2U's kubernetes infrastructure, which assumes that
  # UID 1000 is the one that will be used to run the service. This command also
  # removes the user's group as well. Note that Ubuntu images before noble (24.04)
  # didn't include this user.
  RUN userdel --remove ubuntu
