#include "GamaQtAdapter.hpp"

#include <QColor>
#include <QImage>
#include <QPainter>
#include <QString>

namespace gama {

QtSurface::QtSurface(std::int32_t columns, std::int32_t rows, std::int32_t cellWidth,
                     std::int32_t cellHeight)
    : columns_(columns), rows_(rows), cellWidth_(cellWidth), cellHeight_(cellHeight),
      image_(new QImage(columns * cellWidth, rows * cellHeight,
                        QImage::Format_ARGB32_Premultiplied)) {
    static_cast<QImage *>(image_)->fill(Qt::black);
}

QtSurface::~QtSurface() { delete static_cast<QImage *>(image_); }

QtSurface::QtSurface(const QtSurface &other)
    : columns_(other.columns_), rows_(other.rows_), cellWidth_(other.cellWidth_),
      cellHeight_(other.cellHeight_),
      image_(new QImage(*static_cast<QImage *>(other.image_))) {}

QtSurface::QtSurface(QtSurface &&other) noexcept
    : columns_(other.columns_), rows_(other.rows_), cellWidth_(other.cellWidth_),
      cellHeight_(other.cellHeight_), image_(other.image_) {
    other.image_ = nullptr;
}

QtSurface &QtSurface::operator=(const QtSurface &other) {
    if (this == &other) return *this;
    columns_ = other.columns_;
    rows_ = other.rows_;
    cellWidth_ = other.cellWidth_;
    cellHeight_ = other.cellHeight_;
    if (image_ == nullptr) image_ = new QImage();
    *static_cast<QImage *>(image_) = *static_cast<QImage *>(other.image_);
    return *this;
}

QtSurface &QtSurface::operator=(QtSurface &&other) noexcept {
    if (this == &other) return *this;
    delete static_cast<QImage *>(image_);
    columns_ = other.columns_;
    rows_ = other.rows_;
    cellWidth_ = other.cellWidth_;
    cellHeight_ = other.cellHeight_;
    image_ = other.image_;
    other.image_ = nullptr;
    return *this;
}

void QtSurface::clear(std::uint8_t r, std::uint8_t g, std::uint8_t b) {
    static_cast<QImage *>(image_)->fill(QColor(r, g, b));
}

void QtSurface::fillRect(std::int32_t x, std::int32_t y, std::int32_t width,
                         std::int32_t height, std::uint8_t r, std::uint8_t g,
                         std::uint8_t b) {
    QPainter painter(static_cast<QImage *>(image_));
    painter.fillRect(x * cellWidth_, y * cellHeight_, width * cellWidth_,
                     height * cellHeight_, QColor(r, g, b));
}

void QtSurface::drawText(std::string text, std::int32_t x, std::int32_t y,
                         std::uint8_t r, std::uint8_t g, std::uint8_t b) {
    QPainter painter(static_cast<QImage *>(image_));
    painter.setPen(QColor(r, g, b));
    painter.drawText(x * cellWidth_, (y + 1) * cellHeight_ - 3,
                     QString::fromUtf8(text.data(), static_cast<qsizetype>(text.size())));
}

std::int32_t QtSurface::pixelWidth() const {
    return static_cast<QImage *>(image_)->width();
}

std::int32_t QtSurface::pixelHeight() const {
    return static_cast<QImage *>(image_)->height();
}

} // namespace gama
