/// <summary>
/// Entry point for the Content Builder project, 
/// which when executed will build content according to the "Content Collection Strategy" defined in the Builder class.
/// </summary>
/// <remarks>
/// Make sure to validate the directory paths in the "ContentBuilderParams" for your specific project.
/// For more details regarding the Content Builder, see the MonoGame documentation:
/// https://docs.monogame.net/articles/getting_started/content_pipeline/content_builder/
/// </remarks>

using Microsoft.Xna.Framework.Content.Pipeline;
using MonoGame.Framework.Content.Pipeline.Builder;

var contentCollectionArgs = new ContentBuilderParams()
{
    Mode = ContentBuilderMode.Builder,
    WorkingDirectory = $"{AppContext.BaseDirectory}../../", // path to where your content folder can be located
    SourceDirectory = "Assets", // Not actually needed as this is the default, but added for reference
    Platform = TargetPlatform.DesktopGL
};
var builder = new Builder();

if (args is not null && args.Length > 0)
{
    builder.Run(args);
}
else
{
    builder.Run(contentCollectionArgs);
}

return builder.FailedToBuild > 0 ? -1 : 0;

public class Builder : ContentBuilder
{
    public override IContentCollection GetContentCollection()
    {
        var contentCollection = new ContentCollection();

        // Import all content in the Assets folder using the default importer for their file type.
        contentCollection.Include<WildcardRule>("*");

        // Level files are plain text that the game reads itself, so copy them rather than build them.
        contentCollection.IncludeCopy<WildcardRule>("Levels/*.txt");

        // Please add any custom content collection rules here.

        return contentCollection;
    }
}
