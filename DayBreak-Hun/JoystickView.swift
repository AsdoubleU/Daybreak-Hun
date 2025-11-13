import SwiftUI


let JOYSTICK_SIZE: CGFloat = 200
let HANDLE_SIZE: CGFloat = 60

struct JoystickView: View {
    
    @State private var handleOffset: CGSize = .zero
    let maxRadius: CGFloat = (JOYSTICK_SIZE / 2.0) - (HANDLE_SIZE / 2.0)
    var onJoystickChange: ((Float, Float) -> Void)? = nil
    
    var body: some View
    {
        ZStack {
            Circle().fill(Color.gray.opacity(0.3)).frame(width: JOYSTICK_SIZE, height: JOYSTICK_SIZE).overlay(Circle().stroke(Color.gray, lineWidth: 2))
            Circle().fill(Color.blue).frame(width: HANDLE_SIZE, height: HANDLE_SIZE).offset(handleOffset)
                .gesture(DragGesture().onChanged { gesture in
                    let translation = gesture.translation
                    let distance = sqrt(translation.width * translation.width + translation.height * translation.height)
                    var newOffset = translation
                    if distance > maxRadius {
                        let angle = atan2(translation.height, translation.width)
                        newOffset.width = cos(angle) * maxRadius
                        newOffset.height = sin(angle) * maxRadius
                    }
                    handleOffset = newOffset
                    let x = Float(newOffset.width / maxRadius)
                    let y = Float(-newOffset.height / maxRadius)
                    self.onJoystickChange?(x, y)
                }.onEnded { _ in withAnimation(.spring()) {
                handleOffset = .zero
                self.onJoystickChange?(0.0, 0.0) } } )
        }
    }
    
    
}


#Preview {
    JoystickView()
}
