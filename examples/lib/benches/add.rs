use criterion::{criterion_group, criterion_main, Criterion};
use libonly::add;

// Yeah yeah, its an example not quality code.
fn add_benchmark(c: &mut Criterion) {
    c.bench_function("add", |b| b.iter(|| add(2, 3)));
}

criterion_group!(benches, add_benchmark);
criterion_main!(benches);
