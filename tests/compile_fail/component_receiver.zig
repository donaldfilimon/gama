const g = @import("gama");
const Bad = struct {
    pub fn render(_: *@This(), _: *g.BuildContext) g.Error!g.Node {
        return .empty;
    }
};
test {
    g.composition.validateComponent(Bad);
}
