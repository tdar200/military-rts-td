//! Balance-data loading for the simulation.
//!
//! Unit, building, and tower stats live in data files (RON), not code, so
//! balancing is editing a table rather than recompiling. This crate is the
//! `std` side that parses those tables into the fixed-point types the
//! [`rts_core`] simulation consumes — kept separate from the core so the core
//! stays `no_std` and free of file I/O. Loaders land alongside the systems that
//! need them.
