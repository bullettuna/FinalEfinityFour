# LinkRunCCA notice

`linkruncca_core.v` is derived from the Verilog implementation in
[Topi-ab/linkruncca](https://github.com/Topi-ab/linkruncca), inspected at commit
`a84d236c6e67b3ca511d4dfaa3a11ff605f057de`.

Original author: J. W. Tang. The derived file remains licensed under the GNU
Lesser General Public License, version 3 or (at your option) any later version.
The license text is available at <https://www.gnu.org/licenses/lgpl-3.0.html>.

Local modifications namespace the modules, parameterize the image dimensions,
add deterministic reset handling to pixel-delay registers, and adapt the core
to the existing Sobel/Canny edge stream and frame protocol.

Associated publication:

J. W. Tang et al., "A linked list run-length-based single-pass connected
component analysis for real-time embedded hardware," Journal of Real-Time Image
Processing, 2016. DOI: 10.1007/s11554-016-0590-2.
