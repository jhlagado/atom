// Test-only guard: the production build must not import the retired assembler.
export async function resolve(specifier, context, nextResolve) {
  if (specifier === "@jhlagado/azm" || specifier.startsWith("@jhlagado/azm/")) {
    throw new Error(`AZM import forbidden during ATOM bootstrap: ${specifier}`);
  }
  const result = await nextResolve(specifier, context);
  if (result.url.includes("/node_modules/@jhlagado/azm/")) {
    throw new Error(`AZM module forbidden during ATOM bootstrap: ${result.url}`);
  }
  return result;
}
