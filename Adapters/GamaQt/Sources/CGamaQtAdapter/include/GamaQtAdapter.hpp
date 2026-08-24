#pragma once

#include <cstdint>
#include <string>

namespace gama {

class QtSurface {
public:
    QtSurface(std::int32_t columns, std::int32_t rows, std::int32_t cellWidth = 9,
              std::int32_t cellHeight = 17);
    ~QtSurface();
    QtSurface(const QtSurface &other);
    QtSurface(QtSurface &&other) noexcept;
    QtSurface &operator=(const QtSurface &other);
    QtSurface &operator=(QtSurface &&other) noexcept;

    void clear(std::uint8_t r, std::uint8_t g, std::uint8_t b);
    void fillRect(std::int32_t x, std::int32_t y, std::int32_t width, std::int32_t height,
                  std::uint8_t r, std::uint8_t g, std::uint8_t b);
    void drawText(std::string text, std::int32_t x, std::int32_t y,
                  std::uint8_t r, std::uint8_t g, std::uint8_t b);
    std::int32_t pixelWidth() const;
    std::int32_t pixelHeight() const;

private:
    std::int32_t columns_;
    std::int32_t rows_;
    std::int32_t cellWidth_;
    std::int32_t cellHeight_;
    // Qt types stay out of the Clang module Swift imports. This keeps the
    // boundary header stable and prevents Qt from leaking into clients.
    void *image_;
};

} // namespace gama
