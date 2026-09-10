// stdout and stderr (and sometimes several children) share one desktop log.
// EOF belongs to an input stream; it must not end the shared destination.
export function pipeChildLog(child, log) {
  child.stdout?.pipe(log, {end: false});
  child.stderr?.pipe(log, {end: false});
}
