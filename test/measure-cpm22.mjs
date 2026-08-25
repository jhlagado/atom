import { expectedRepresentativeProgram, runCpm22Atom } from "./cpm22-support.mjs";

const expected = await expectedRepresentativeProgram();
const result = await runCpm22Atom();
console.log(JSON.stringify({
  residentBytes: result.atomBytes.length,
  generatedBytes: expected.bytes.length,
  instructions: result.atomInstructions,
  tStates: result.atomCycles,
  commandLoadAndProgramInstructions: result.commandInstructions,
  commandLoadAndProgramTStates: result.commandCycles,
  minimumSp: result.atomMinimumSp,
  stackHighWaterBytes: 0xe400 - result.atomMinimumSp,
  entrySp: result.entrySp,
  returnSp: result.returnSp,
  bdosCalls: result.atomBdosCalls,
  transcript: result.atomTranscript,
}, undefined, 2));
