const g = @import("gama");
const Bad = struct {
    pub fn render(_: *const @This(), _: *g.BuildContext) g.Node {
        return .empty;
    }
};
test {
    g.composition.validateComponent(Bad);
}
