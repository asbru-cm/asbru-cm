# AppImage Packaging

Ásbrú can be distributed as an AppImage, with the necessary code for this inside the `dist/appimage-raw` folder. The embedded binaries are currently based on Alpine Linux, which is the base OS for the build. The generated AppImage is quite large but embeds all of the needed Perl and GTK libraries and even libc so it's expected to work on most, if not all, Linux systems.

## Building

To build the AppImage, you will need Docker installed and accessible from your POSIX shell. Then, just cd to the root directory of the project, and run: `./dist/appimage-raw/make_appimage.sh`. It will be available on `./dist/appimage-raw/build`.

## Code Support

Code changes were needed to make the AppImage work independently of the particular system that is running it, since Ásbrú is a complex application which invokes multiple subprocesses and interacts with the OS in various different ways. The reason for each will be documented here for future maintainers' knowledge of the needed adjustments.

### Additional Environment Variables

Some environment variables were created when running as an AppImage so that the code can use them for adjusting the way it runs subprocesses.

The environment variables `ASBRU_ENV_FOR_EXTERNAL` and `ASBRU_ENV_FOR_INTERNAL` contain strings that, when prepended to shell commands, use either the original environment variables (for invoking programs external to the AppImage) or the internal modified environment variables (for invoking programs internal to the AppImage where the invocation is intermediated by a program external to the AppImage).

The environment variable `ASBRU_SUB_CWD` is created in-code and is necessary because using `cd` is no longer a viable approach when supporting AppImages, since the process works by relinking the LD header binaries inside the AppImage to the relative path of the embedded libc implementation, so when creating the `asbru_conn` subprocess, the desired shell directory must be communicated somehow.

Environent variable `ASBRU_IS_APPIMAGE` is also set to `1`, if any future specific checks need to be done.
