import { load } from "./qs-loader.js";
import { rail } from "./rail.js";

load(["colors.css", "theme.css"]);
// колонка навигации — только в главном окне
if (document.title === "Steam") rail();
