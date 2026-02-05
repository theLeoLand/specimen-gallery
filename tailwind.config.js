module.exports = {
  darkMode: 'class',
  content: [
    './app/views/**/*.html.erb',
    './app/helpers/**/*.rb',
    './app/assets/stylesheets/**/*.css',
    './app/javascript/**/*.js'
  ],
  theme: {
    extend: {
      fontFamily: {
        serif: ['Instrument Serif', 'serif'],
        sans: ['DM Sans', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
}

