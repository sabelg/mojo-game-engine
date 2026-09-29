"""Typed FIFO events. Drain transfers a batch; new events wait for the next drain."""
struct EventQueue[T: Copyable & Deinitable]:
    var pending: List[Self.T]

    def __init__(out self):
        self.pending = List[Self.T]()

    def emit(mut self, var event: Self.T):
        self.pending.append(event^)

    def drain(mut self) -> List[Self.T]:
        var batch = self.pending^
        self.pending = List[Self.T]()
        return batch^
