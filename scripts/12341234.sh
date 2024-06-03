mkdir -p $HOME/.packages/zig
curl -N -L https://ziglang.org/download/0.12.0/zig-linux-x86_64-0.12.0.tar.xz -o $HOME/.packages/zig/zig-0.12.tar.xz
tar --totals -xf $HOME/.packages/zig/zig-0.12.tar.xz -C $HOME/.packages/zig
ln -sf $HOME/.packages/zig/zig-linux-x86_64-0.12.0/zig $HOME/.local/bin/zig
