@page dunstblick-layout-language Dunstblick Layout Language
@brief Description of the @ref dunstblick Layout Language

@todo Write this page

## Example

```dll
Picture
{
  margins: 0;
	image: resource("wallpaper");
	image-scaling: cover;
	DockLayout
	{
		Label
		{
			dock-site: bottom;
			text: bind("current-artist"); 
		}
		Label
		{
			dock-site: bottom;
			text: bind("current-song");
		}
		Picture
		{
			image: bind("current-albumart");
			image-scaling: zoom;
			vertical-alignment: middle;
			horizontal-alignment: center;
		}
	}
}
```