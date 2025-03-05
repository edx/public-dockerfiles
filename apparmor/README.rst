AppArmor profiles
#################

If a service's Docker image is to be deployed with an AppArmor profile, the profile can be stored here.

Caveats:

* We don't have an automated deployment mechanism for AppArmor profiles, and in particular we don't have a way to coordinate image updates and profile updates. Use an expand/contract pattern when coordinating changes between a Dockerfile and an AppArmor profile, and double-check that changes have been applied on one side before proceeding with the other.
* The name of the profile, as defined in the text of the file, is the part that AppArmor cares about. The filename is irrelevant. We should probably keep the two in sync, though.

  * Bear in mind that changing a profile name is an annoying and manual process, so think carefully when picking a name. Prefixing with ``openedx_`` may help operators.

See `<https://manpages.ubuntu.com/manpages/noble/man5/apparmor.d.5.html>`__ or ``man apparmor.d`` for documentation of syntax and options.
