#include "../include/sdl2++/exception"
#include "../include/sdl2++/renderer"
#include "../include/sdl2++/texture"

#include <stdexcept>
#include <tuple>

const char * sdl2::exception::what() const noexcept
{
    return SDL_GetError();
}

sdl2::renderer::renderer(SDL_Window * window, Uint32 flags, int index) : ptr(SDL_CreateRenderer(window, index, flags))
{
    if (not ptr)
        throw sdl2::exception();
}

sdl2::renderer::renderer(SDL_Surface * surface) : ptr(SDL_CreateSoftwareRenderer(surface))
{
    if (not ptr)
        throw sdl2::exception();
}

void sdl2::renderer::clear()
{
    SDL_RenderClear(*this);
}

void sdl2::renderer::copy(SDL_Texture * texture)
{
    SDL_RenderCopy(*this, texture, nullptr, nullptr);
}

void sdl2::renderer::copy(SDL_Texture * texture, const SDL_Rect & dest)
{
    SDL_RenderCopy(*this, texture, nullptr, &dest);
}

void sdl2::renderer::copy(SDL_Texture * texture, const SDL_Rect & dest, const SDL_Rect & src)
{
    SDL_RenderCopy(*this, texture, &src, &dest);
}

void sdl2::renderer::drawLine(int x1, int y1, int x2, int y2)
{
    SDL_RenderDrawLine(*this, x1, y1, x2, y2);
}

void sdl2::renderer::drawLine(SDL_Point p0, SDL_Point p1)
{
    SDL_RenderDrawLine(*this, p0.x, p0.y, p1.x, p1.y);
}

void sdl2::renderer::drawLines(const SDL_Point * points, size_t count)
{
    SDL_RenderDrawLines(*this, points, static_cast<int>(count));
}

void sdl2::renderer::drawPoint(int x, int y)
{
    SDL_RenderDrawPoint(*this, x, y);
}

void sdl2::renderer::drawPoints(const SDL_Point * points, size_t count)
{
    SDL_RenderDrawPoints(*this, points, static_cast<int>(count));
}

void sdl2::renderer::drawRect(int x, int y, int w, int h)
{
    SDL_Rect rect = {x, y, w, h};
    SDL_RenderDrawRect(*this, &rect);
}

void sdl2::renderer::drawRect(const SDL_Rect & rect)
{
    SDL_RenderDrawRect(*this, &rect);
}

void sdl2::renderer::drawRects(const SDL_Rect * rects, size_t count)
{
    SDL_RenderDrawRects(*this, rects, static_cast<int>(count));
}

void sdl2::renderer::fillRect(const SDL_Rect & rect)
{
    SDL_RenderFillRect(*this, &rect);
}

void sdl2::renderer::fillRects(const SDL_Rect * rects, size_t count)
{
    SDL_RenderFillRects(*this, rects, static_cast<int>(count));
}

SDL_Rect sdl2::renderer::getClipRect() const
{
    SDL_Rect result;
    SDL_RenderGetClipRect(*this, &result);
    return result;
}

bool sdl2::renderer::isTargetSupported() const
{
    return SDL_RenderTargetSupported(*this);
}

bool sdl2::renderer::hasIntegerScale() const
{
    return SDL_RenderGetIntegerScale(*this);
}

std::tuple<int, int> sdl2::renderer::getLogicalSize() const
{
    int w, h;
    SDL_RenderGetLogicalSize(*this, &w, &h);
    return std::make_tuple(w, h);
}

std::tuple<float, float> sdl2::renderer::getScale() const
{
    float h, v;
    SDL_RenderGetScale(*this, &h, &v);
    return std::make_tuple(h, v);
}

SDL_Rect sdl2::renderer::getViewport() const
{
    SDL_Rect res;
    SDL_RenderGetViewport(*this, &res);
    return res;
}

bool sdl2::renderer::isClipEnabled() const
{
    return SDL_RenderIsClipEnabled(*this);
}

void sdl2::renderer::present()
{
    SDL_RenderPresent(*this);
}

void sdl2::renderer::readPixels(SDL_Rect region, Uint32 format, void * target, size_t pitch)
{
    SDL_RenderReadPixels(*this, &region, format, target, static_cast<int>(pitch));
}

void sdl2::renderer::resetClipRect()
{
    SDL_RenderSetClipRect(*this, nullptr);
}

void sdl2::renderer::setClipRect(const SDL_Rect & rect)
{
    SDL_RenderSetClipRect(*this, &rect);
}

void sdl2::renderer::enableIntegerScale()
{
    SDL_RenderSetIntegerScale(*this, SDL_TRUE);
}

void sdl2::renderer::disableIntergerScale()
{
    SDL_RenderSetIntegerScale(*this, SDL_FALSE);
}

void sdl2::renderer::setIntegerScale(bool value)
{
    SDL_RenderSetIntegerScale(*this, value ? SDL_TRUE : SDL_FALSE);
}

void sdl2::renderer::setLogicalSize(int w, int h)
{
    SDL_RenderSetLogicalSize(*this, w, h);
}

void sdl2::renderer::setScale(float h, float v)
{
    SDL_RenderSetScale(*this, h, v);
}

void sdl2::renderer::setViewport(const SDL_Rect & rect)
{
    SDL_RenderSetViewport(*this, &rect);
}

void sdl2::renderer::setViewport(int x, int y, int w, int h)
{
    SDL_Rect rect = {x, y, w, h};
    SDL_RenderSetViewport(*this, &rect);
}

void sdl2::renderer::setBlendMode(SDL_BlendMode blendMode)
{
    if (SDL_SetRenderDrawBlendMode(*this, blendMode) < 0)
        throw sdl2::exception();
}

SDL_BlendMode sdl2::renderer::getBlendMode() const
{
    SDL_BlendMode mode;
    if (SDL_GetRenderDrawBlendMode(*this, &mode) < 0)
        throw sdl2::exception();
    return mode;
}

void sdl2::renderer::setColor(Uint8 r, Uint8 g, Uint8 b, Uint8 a)
{
    if (SDL_SetRenderDrawColor(*this, r, g, b, a) < 0)
        throw sdl2::exception();
}

void sdl2::renderer::setColor(const SDL_Color & color)
{
    if (SDL_SetRenderDrawColor(*this, color.r, color.g, color.b, color.a) < 0)
        throw sdl2::exception();
}

SDL_Color sdl2::renderer::getColor() const
{
    SDL_Color color;
    if (SDL_GetRenderDrawColor(*this, &color.r, &color.g, &color.b, &color.a) < 0)
        throw sdl2::exception();
    return color;
}

void sdl2::renderer::setRenderTarget(SDL_Texture * target)
{
    if (SDL_SetRenderTarget(*this, target) < 0)
        throw sdl2::exception();
}

SDL_Texture * sdl2::renderer::getRenderTarget() const
{
    return SDL_GetRenderTarget(*this);
}

std::tuple<int, int> sdl2::renderer::getOutputSize() const
{
    int w, h;
    if (SDL_GetRendererOutputSize(*this, &w, &h) < 0)
        throw sdl2::exception();
    return std::make_tuple(w, h);
}

sdl2::texture::texture(SDL_Texture *&& init) : ptr(init)
{
    if (not ptr)
        throw std::invalid_argument("init must not be nullptr!");
}

sdl2::texture::texture(SDL_Renderer * ren, int w, int h, SDL_PixelFormatEnum format, SDL_TextureAccess access) :
    ptr(SDL_CreateTexture(ren, format, access, w, h))
{
    if (not ptr)
        throw sdl2::exception();
}

sdl2::texture::texture(SDL_Renderer * ren, SDL_Surface * surf) : ptr(SDL_CreateTextureFromSurface(ren, surf))
{
    if (not ptr)
        throw sdl2::exception();
}

std::tuple<SDL_PixelFormatEnum, SDL_TextureAccess, int, int> sdl2::texture::query() const
{
    Uint32 format;
    int access;
    int w;
    int h;

    if (SDL_QueryTexture(*this, &format, &access, &w, &h) < 0)
        throw sdl2::exception();

    return std::make_tuple(SDL_PixelFormatEnum(format), SDL_TextureAccess(access), w, h);
}

void sdl2::texture::update(void * pixels, size_t pitch)
{
    if (SDL_UpdateTexture(*this, nullptr, pixels, static_cast<int>(pitch)) < 0)
        throw sdl2::exception();
}

void sdl2::texture::update(const SDL_Rect & rect, void * pixels, size_t pitch)
{
    if (SDL_UpdateTexture(*this, &rect, pixels, static_cast<int>(pitch)) < 0)
        throw sdl2::exception();
}

Uint8 sdl2::texture::getAlphaMod() const
{
    Uint8 alpha;
    if (SDL_GetTextureAlphaMod(*this, &alpha) < 0)
        throw sdl2::exception();
    return alpha;
}

SDL_BlendMode sdl2::texture::getBlendMode() const
{
    SDL_BlendMode mode;
    if (SDL_GetTextureBlendMode(*this, &mode) < 0)
        throw sdl2::exception();
    return mode;
}

SDL_Color sdl2::texture::getColorMod() const
{
    SDL_Color col = {0, 0, 0, 0xFF};
    if (SDL_GetTextureColorMod(*this, &col.r, &col.g, &col.b) < 0)
        throw sdl2::exception();
    return col;
}

std::tuple<void *, size_t> sdl2::texture::lock()
{
    void * _ptr;
    int pitch;
    if (SDL_LockTexture(*this, nullptr, &_ptr, &pitch) < 0)
        throw sdl2::exception();
    return std::make_tuple(_ptr, size_t(pitch));
}

std::tuple<void *, size_t> sdl2::texture::lock(const SDL_Rect & rect)
{
    void * _ptr;
    int pitch;
    if (SDL_LockTexture(*this, &rect, &_ptr, &pitch) < 0)
        throw sdl2::exception();
    return std::make_tuple(_ptr, size_t(pitch));
}

void sdl2::texture::setAlphaMod(Uint8 alpha)
{
    if (SDL_SetTextureAlphaMod(*this, alpha) < 0)
        throw sdl2::exception();
}

void sdl2::texture::setBlendMode(SDL_BlendMode mode)
{
    if (SDL_SetTextureBlendMode(*this, mode) < 0)
        throw sdl2::exception();
}

void sdl2::texture::setColorMod(Uint8 r, Uint8 g, Uint8 b)
{
    if (SDL_SetTextureColorMod(*this, r, g, b) < 0)
        throw sdl2::exception();
}

void sdl2::texture::setColorMod(SDL_Color color)
{
    if (SDL_SetTextureColorMod(*this, color.r, color.g, color.b) < 0)
        throw sdl2::exception();
}

void sdl2::texture::unlock()
{
    SDL_UnlockTexture(*this);
}
