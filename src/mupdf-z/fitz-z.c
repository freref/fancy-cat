#include "fitz-z.h"

fz_document *fz_open_document_z(fz_context *ctx, const char *filename) {
  fz_try(ctx) { return fz_open_document(ctx, filename); }
  fz_catch(ctx) { return NULL; }
}

int fz_count_pages_z(fz_context *ctx, fz_document *doc) {
  fz_try(ctx) { return fz_count_pages(ctx, doc); }
  fz_catch(ctx) { return 0; }
}

fz_page *fz_load_page_z(fz_context *ctx, fz_document *doc, int page_number) {
  fz_try(ctx) { return fz_load_page(ctx, doc, page_number); }
  fz_catch(ctx) { return NULL; }
}
