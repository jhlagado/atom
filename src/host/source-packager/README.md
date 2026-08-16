# Source-packager boundary

This directory contains Atom's language-neutral host services for source
identity, dependency resolution, source plans, placement, and provenance.
The modules may import Node built-ins and other files in this directory. They
must not import Atom-specific syntax or resident assembler code.

Atom owns this implementation while the Atom and Nucleus host requirements are
still being measured. The modules retain a separate public boundary so the
shared services can move into a Debug80 package or app later without changing
the resident assembler interface or the SP1 interchange.
