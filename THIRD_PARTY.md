# Third-party material

Original compiler, adapter, plugin and VM definitions in this repository are MIT.
Tests fetch Lunar revision `a011820d4588f64dcb249b7ea025d9e7e0db1593` from
https://github.com/lunar-linux/lunar. Its existing GPL 2 notices remain intact;
the native installer is run unmodified and its LICENSE is preserved in the VM.

The VM also uses the actual installwatch shared library from the pinned nixpkgs
checkinstall 1.8.3 package. Its upstream sources and GPL 2 license are independent
of this repository's MIT code. The compiler exports both log-variable names for
compatibility; it does not replace the library or native package state with mocks.
