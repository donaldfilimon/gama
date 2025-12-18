import Foundation

/// A protocol that declares a type that can transmit a sequence of values
/// over time.
///
/// This is a simplified publisher protocol similar to Combine's Publisher,
/// designed for use in the view system without external dependencies.
///
/// Swift 6.2: Enhanced with improved Sendable conformance
public protocol Publisher: @retroactive Sendable {
    /// The kind of values published by this publisher.
    associatedtype Output
    
    /// The kind of errors this publisher might publish.
    associatedtype Failure: Error
    
    /// Attaches the specified subscriber to this publisher.
    ///
    /// - Parameter subscriber: The subscriber to attach to this publisher.
    func receive<S>(subscriber: S) where S: Subscriber, Self.Failure == S.Failure, Self.Output == S.Input
}

/// A protocol that declares a type that can receive input from a publisher.
public protocol Subscriber: AnyObject {
    /// The kind of values this subscriber receives.
    associatedtype Input
    
    /// The kind of errors this subscriber might receive.
    associatedtype Failure: Error
    
    /// Tells the subscriber that it has successfully subscribed to the publisher.
    ///
    /// - Parameter subscription: A subscription instance.
    func receive(subscription: Subscription)
    
    /// Tells the subscriber that the publisher has produced an element.
    ///
    /// - Parameter input: The published element.
    /// - Returns: A `Subscribers.Demand` instance indicating how many more
    ///   elements the subscriber expects to receive.
    func receive(_ input: Self.Input) -> Subscribers.Demand
    
    /// Tells the subscriber that the publisher has completed publishing,
    /// either normally or with an error.
    ///
    /// - Parameter completion: A `Completion` case indicating whether
    ///   publishing completed normally or with an error.
    func receive(completion: Subscribers.Completion<Self.Failure>)
}

/// A protocol representing the connection between a publisher and a subscriber.
public protocol Subscription: Cancellable {
    /// Tells a publisher that it may send more values to the subscriber.
    ///
    /// - Parameter demand: The number of elements the subscriber wants to receive.
    func request(_ demand: Subscribers.Demand)
}

/// A protocol indicating that an activity or action supports cancellation.
public protocol Cancellable {
    /// Cancel the activity.
    func cancel()
}

/// A type-erased cancellable object.
public final class AnyCancellable: Cancellable {
    private let _cancel: () -> Void
    
    public init(_ cancel: @escaping () -> Void) {
        self._cancel = cancel
    }
    
    public init<C: Cancellable>(_ cancellable: C) {
        var cancellable = cancellable
        self._cancel = { cancellable.cancel() }
    }
    
    public func cancel() {
        _cancel()
    }
}

/// A namespace for types related to the `Subscriber` protocol.
public enum Subscribers {
    /// A requested number of items, sent to a publisher from a subscriber.
    public struct Demand: Equatable, Comparable, Hashable, Codable, Sendable {
        public static let unlimited = Demand(rawValue: Int.max)
        public static let none = Demand(rawValue: 0)
        
        private let rawValue: Int
        
        private init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static func + (lhs: Demand, rhs: Demand) -> Demand {
            Demand(rawValue: min(lhs.rawValue + rhs.rawValue, Int.max))
        }
        
        public static func += (lhs: inout Demand, rhs: Demand) {
            lhs = lhs + rhs
        }
        
        public static func * (lhs: Demand, rhs: Int) -> Demand {
            Demand(rawValue: min(lhs.rawValue * rhs, Int.max))
        }
        
        public static func *= (lhs: inout Demand, rhs: Int) {
            lhs = lhs * rhs
        }
        
        public static func - (lhs: Demand, rhs: Demand) -> Demand {
            Demand(rawValue: max(lhs.rawValue - rhs.rawValue, 0))
        }
        
        public static func -= (lhs: inout Demand, rhs: Demand) {
            lhs = lhs - rhs
        }
        
        public static func < (lhs: Demand, rhs: Demand) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        public static func == (lhs: Demand, rhs: Demand) -> Bool {
            lhs.rawValue == rhs.rawValue
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(rawValue)
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            rawValue = try container.decode(Int.self)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
    
    /// A signal that a publisher doesn't have additional elements to publish.
    public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }
}

/// Extension to provide convenience methods for publishers.
extension Publisher {
    /// Attaches a subscriber with closure-based behavior.
    ///
    /// - Parameter receiveValue: The closure to execute when receiving a value.
    /// - Returns: A cancellable instance.
    public func sink(
        receiveValue: @escaping (Output) -> Void
    ) -> AnyCancellable where Failure == Never {
        let subscriber = SinkSubscriber(receiveValue: receiveValue)
        receive(subscriber: subscriber)
        return AnyCancellable(subscriber)
    }
    
    /// Attaches a subscriber with closure-based behavior.
    ///
    /// - Parameters:
    ///   - receiveCompletion: The closure to execute when receiving completion.
    ///   - receiveValue: The closure to execute when receiving a value.
    /// - Returns: A cancellable instance.
    public func sink(
        receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
        receiveValue: @escaping (Output) -> Void
    ) -> AnyCancellable {
        let subscriber = SinkSubscriber(
            receiveCompletion: receiveCompletion,
            receiveValue: receiveValue
        )
        receive(subscriber: subscriber)
        return AnyCancellable(subscriber)
    }
}

private class SinkSubscriber<Input, Failure: Error>: Subscriber, Cancellable {
    typealias Input = Input
    typealias Failure = Failure
    
    private let receiveValue: (Input) -> Void
    private let receiveCompletion: ((Subscribers.Completion<Failure>) -> Void)?
    private var subscription: Subscription?
    
    init(receiveValue: @escaping (Input) -> Void) {
        self.receiveValue = receiveValue
        self.receiveCompletion = nil
    }
    
    init(
        receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
        receiveValue: @escaping (Input) -> Void
    ) {
        self.receiveCompletion = receiveCompletion
        self.receiveValue = receiveValue
    }
    
    func receive(subscription: Subscription) {
        self.subscription = subscription
        subscription.request(.unlimited)
    }
    
    func receive(_ input: Input) -> Subscribers.Demand {
        receiveValue(input)
        return .unlimited
    }
    
    func receive(completion: Subscribers.Completion<Failure>) {
        receiveCompletion?(completion)
        subscription = nil
    }
    
    func cancel() {
        subscription?.cancel()
        subscription = nil
    }
}