//! Compiles the demo UI ahead of time, so the spike needs no interpreter.

fn main() {
    if let Err(err) = slint_build::compile("ui/demo.slint") {
        // Build scripts report failure by exit status; there is no caller to return to.
        println!("cargo::error={err}");
    }
}
