# Third-party engines

SlimLuma does not currently bundle third-party executables. It discovers
compatible command-line tools installed by the user and invokes them as
separate processes with explicit argument arrays.

| Engine | Purpose | License note | Project |
| --- | --- | --- | --- |
| ImageMagick | Image compression, resize, metadata and conversion | ImageMagick License; attribution is required if redistributed | https://imagemagick.org |
| FFmpeg | Video transcode and compression | Primarily LGPL; a particular build may become GPL depending on enabled components | https://ffmpeg.org |
| qpdf | PDF stream and object optimization | Apache License 2.0 | https://qpdf.sourceforge.io |
| Ghostscript | Optional aggressive PDF compression | AGPL or commercial license; not bundled | https://ghostscript.com |

Before distributing a build that bundles any engine, audit the exact binary,
its build configuration, codecs/delegates and required notices. In particular,
do not assume that every FFmpeg binary has the same license.

## Linked Swift packages

The standalone `slimluma` command-line interface links the following package:

| Package | Purpose | License | Project |
| --- | --- | --- | --- |
| Swift Argument Parser 1.8.2 | Type-safe CLI parsing and generated help | Apache License 2.0 | https://github.com/apple/swift-argument-parser |

The release archive includes this notice alongside the command-line binary.
