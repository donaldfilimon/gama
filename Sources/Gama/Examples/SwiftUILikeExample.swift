import Foundation

/// Example demonstrating the SwiftUI-like unified API
///
/// This example shows how to use the new declarative API:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///     }
/// }
///
/// struct ContentView: View {
///     @State private var count = 0
///     
///     var body: some View {
///         VStack {
///             Text("Count: \(count)")
///             Button("Increment") {
///                 count += 1
///             }
///         }
///     }
/// }
/// ```

#if false
// Example code (disabled to avoid compilation issues with incomplete implementation)

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ExampleContentView()
        }
    }
}

struct ExampleContentView: View {
    @State private var count = 0
    @State private var text = "Hello, Gama!"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Count: \(count)")
                .font(.system(size: 24))
                .foregroundColor(.blue)
            
            HStack(spacing: 10) {
                Button("Decrement") {
                    count -= 1
                }
                
                Button("Increment") {
                    count += 1
                }
            }
            
            TextField("Enter text", text: $text)
            
            RectangleShape()
                .fill(.red)
                .frame(width: 100, height: 100)
            
            Circle()
                .stroke(.blue, lineWidth: 2)
                .frame(width: 80, height: 80)
        }
        .padding()
    }
}

#endif