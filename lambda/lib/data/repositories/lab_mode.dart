/// True while the app runs inside the dev flow lab's sandbox.
///
/// Why a flag is needed at all: the lab swaps the global database for a
/// scratch one (see `swapDatabase`) and then runs the REAL screens and view
/// models against it, so the whole program/workout/review flow can be
/// exercised with fake data. Repositories read `ps.db` per call, so every
/// read and every local write follows the swap — but two of them talk to
/// Supabase over REST as well: `ProgramRepository` and `ProgramRunRepository`
/// create program, block and run rows remotely and mirror them locally. Those
/// are the only paths left that would reach the user's real account, and in
/// lab mode they take a local-only remote instead.
///
/// Set and cleared by the lab screen (`features/dev/lab/`) around a sandbox
/// session. Process-memory only — a restart clears it whatever happens — and
/// the lab clears it on teardown, which is the normal path.
bool labMode = false;
