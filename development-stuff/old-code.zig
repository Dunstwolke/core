test {
    if (self.mode.isAppMenuVisible()) {
        const app_menu_button_rect = self.getMenuButtonRectangle(0);
        const app_menu_rect = self.getAppMenuRectangle();
        const layout = self.getAppMenuLayout();
        const margin = self.config.app_menu.margins;
        const button_size = self.config.app_menu.button_size;

        // draw dimmed background
        try renderer.fillRectangle(
            Rectangle{
                .x = 0,
                .y = 0,
                .width = self.size.width,
                .height = self.size.height,
            },
            self.config.app_menu.dimmer,
        );

        // overdraw button
        {
            const button_rect = app_menu_button_rect;
            const icon_area = Rectangle{
                .x = button_rect.x + 1,
                .y = button_rect.y + 1,
                .width = button_rect.width - 2,
                .height = button_rect.height - 2,
            };

            try renderer.fillRectangle(icon_area, self.config.app_menu.background);
            try renderer.drawRectangle(button_rect, self.config.app_menu.outline);

            try self.drawIcon(icon_area, &icons.app_menu, Color.white);
        }

        // draw menu
        try renderer.fillRectangle(app_menu_rect, self.config.app_menu.background);
        try renderer.drawRectangle(app_menu_rect, self.config.app_menu.outline);

        try renderer.drawLine(
            app_menu_rect.x + margin + layout.cols * (margin + button_size),
            app_menu_rect.y + 1,
            app_menu_rect.x + margin + layout.cols * (margin + button_size),
            app_menu_rect.y + app_menu_rect.height - 1,
            self.config.app_menu.outline,
        );
        // draw menu connector
        {
            var i: u15 = 0;
            while (i < self.config.workspace_bar.margins + 2) : (i += 1) {
                switch (self.config.workspace_bar.location) {
                    .left => {
                        const x = app_menu_button_rect.x + app_menu_button_rect.width - 1 + i;
                        try renderer.setPixel(x, app_menu_button_rect.y, self.config.app_menu.outline);
                        try renderer.setPixel(x, app_menu_button_rect.y + app_menu_button_rect.height + i, self.config.app_menu.outline);
                        try renderer.drawLine(
                            x,
                            app_menu_button_rect.y + 1,
                            x,
                            app_menu_button_rect.y + app_menu_button_rect.height - 1 + i,
                            self.config.app_menu.background,
                        );
                    },
                    .right => {
                        const x = app_menu_button_rect.x - i;
                        try renderer.setPixel(x, app_menu_button_rect.y, self.config.app_menu.outline);
                        try renderer.setPixel(x, app_menu_button_rect.y + app_menu_button_rect.height + i, self.config.app_menu.outline);
                        try renderer.drawLine(
                            x,
                            app_menu_button_rect.y + 1,
                            x,
                            app_menu_button_rect.y + app_menu_button_rect.height - 1 + i,
                            self.config.app_menu.background,
                        );
                    },
                    .top => {
                        const y = app_menu_button_rect.y + app_menu_button_rect.height - 1 + i;
                        try renderer.setPixel(app_menu_button_rect.x, y, self.config.app_menu.outline);
                        try renderer.setPixel(app_menu_button_rect.x + app_menu_button_rect.width + i, y, self.config.app_menu.outline);
                        try renderer.drawLine(
                            app_menu_button_rect.x + 1,
                            y,
                            app_menu_button_rect.x + app_menu_button_rect.width - 1 + i,
                            y,
                            self.config.app_menu.background,
                        );
                    },
                    .bottom => {
                        const y = app_menu_button_rect.y - i;
                        try renderer.setPixel(app_menu_button_rect.x, y, self.config.app_menu.outline);
                        try renderer.setPixel(app_menu_button_rect.x + app_menu_button_rect.width + i, y, self.config.app_menu.outline);
                        try renderer.drawLine(
                            app_menu_button_rect.x + 1,
                            y,
                            app_menu_button_rect.x + app_menu_button_rect.width - 1 + i,
                            y,
                            self.config.app_menu.background,
                        );
                    },
                }
            }
        }

        for (self.available_apps.items) |app, app_index| {
            const rect = self.getAppButtonRectangle(app_index);

            // Do not draw the dragged app in the menu
            if (dragged_app_index != null and (dragged_app_index.? == app_index))
                continue;

            try self.renderButton(
                rect,
                app.button_state,
                self.config.app_menu.button_theme,
                app.application.display_name,
                app.application.icon orelse icons.app_placeholder,
                1.0,
            );
        }
    }
}
