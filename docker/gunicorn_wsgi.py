# frappe.app:application only gets wrapped with static-file-serving
# middleware inside frappe.app.serve() (the bench dev server path) — gunicorn
# imports the bare app object, which never serves /assets or /files itself.
# Normally nginx serves those paths directly; this image has no nginx, so
# reapply the same wrapping frappe.app.serve() does, by hand.
import os

from frappe.app import application as _application
from frappe.middlewares import StaticDataMiddleware
from werkzeug.middleware.shared_data import SharedDataMiddleware

_sites_path = os.environ.get("SITES_PATH", ".")

application = SharedDataMiddleware(_application, {"/assets": os.path.join(_sites_path, "assets")})
application = StaticDataMiddleware(application, {"/files": os.path.abspath(_sites_path)})
