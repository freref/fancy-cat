// Types used in document handlers
pub const EncodedImage = struct { base64: []const u8, width: u16, height: u16 };
pub const DocumentError = error{ FailedToCreateContext, FailedToOpenDocument, InvalidPageNumber };
pub const ScrollDirection = enum { Up, Down, Left, Right };
