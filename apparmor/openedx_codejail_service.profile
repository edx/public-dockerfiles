# AppArmor profile for running codejail-service.
#
# Changes to this profile must be coordinated carefully with changes to the
# Dockerfile. See README for additional cautions.
#
#                         #=========#
#                         # WARNING #
#                         #=========#
#
# Failure to apply a secure apparmor profile *will* likely result in a
# full compromise of the host by an attacker. AppArmor is *mandatory*
# for using codejail -- this is not just for hardening.



# Sets standard variables used by abstractions/base, later. Controlled
# by OS, see /etc/apparmor.d/tunables/global for contents.
include <tunables/global>

# Require that the system understands the feature set that this policy was written
# for. If we didn't include this, then on Ubuntu >= 22.04, AppArmor might assume
# the wrong feature set was requested, and some rules might become too permissive.
# See https://github.com/netblue30/firejail/issues/3659#issuecomment-711074899
abi <abi/3.0>,

# This outer profile applies to the entire container, and isn't as
# important as the inner (codejail_sandbox) profile. If the inner profile doesn't work, it's not likely that
# the outer one is going to help. But there may be some small value in
# defense-in-depth, as it's possible that a bug in the codejail_sandbox (inner)
# profile isn't present in the outer one.
profile openedx_codejail_service flags=(mediate_deleted) {

    # Allow access to a variety of commonly needed, generally safe things
    # (such as reading /dev/random, free memory, etc.)
    #
    # Manpage: "Includes files that should be readable and writable in all profiles."
    include <abstractions/base>

    # Filesystem access -- self-explanatory
    file,

    # netlink is needed for sudo's interprocess communication
    network netlink raw,

    # Allow all of the various network operations required to listen, accept connection, etc.
    network tcp,
    # But then deny making a new *outbound* connection.
    deny network (connect) tcp,

    # Required for sudoing to sandbox
    capability setuid setgid audit_write,
    # Allow sending a kill signal
    capability kill,

    # Allow sending a kill signal to the codejail_sandbox subprofile when the execution
    # runs beyond time limits.
    signal (send) set=(kill) peer=openedx_codejail_service//codejail_sandbox,

    # Allow receiving a kill signal (and other signals) from container orchestration.
    signal (receive),

    # The core of the confinement: When the sandbox Python is executed, switch to
    # the (extremely constrained) codejail_sandbox profile.
    #
    # This path needs to be coordinated with the Dockerfile and Django settings.
    #
    # Manpage: "Cx: transition to subprofile on execute -- scrub the environment"
    /sandbox/venv/bin/python Cx -> codejail_sandbox,

    # This is the important apparmor profile -- the one that actually
    # constrains the sandbox Python process.
    #
    # mediate_deleted is not well documented, but it seems to indicate that
    # apparmor will continue to make policy decisions in cases where a confined
    # executable has a handle to a file's inode even after the file is removed
    # from the filesystem.
    profile codejail_sandbox flags=(mediate_deleted) {

        # This inner profile also gets general access to "safe"
        # actions; we could list those explicitly out of caution but
        # it could get pretty verbose.
        include <abstractions/base>

        # Read and run binaries and libraries in the virtualenv. This
        # includes the sandbox's copy of Python as well as any
        # dependencies that have been installed for inclusion in
        # sandboxes.
        #
        # m: executable mapping, required for shared libraries used by some
        #    Python dependencies with C compontents, eg `nltk`.
        /sandbox/venv/** rm,

        # Allow access to the temporary directories that are set up by
        # codejail, one for each code-exec call. Each /tmp/code-XXXXX
        # contains one execution.
        #
        # Codejail has a hardcoded reference to this file path, although the
        # use of /tmp specifically may be controllable with environment variables:
        # https://github.com/openedx/codejail/blob/0165d9ca351/codejail/util.py#L15
        /tmp/codejail-*/ r,
        /tmp/codejail-*/** rw,

        # Allow receiving a kill signal from the webapp when the execution
        # runs beyond time limits.
        signal (receive) set=(kill) peer=openedx_codejail_service,
    }
}
