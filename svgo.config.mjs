export default {
  multipass: true,
  js2svg: {
    pretty: true,
    indent: 2,
  },
  plugins: [
    {
      name: 'preset-default',
      params: {
        overrides: {
          cleanupIds: false,
          removeDesc: false,
        },
      },
    },
    'removeDimensions',
    {
      name: 'removeAttrs',
      params: {
        attrs: 'filter',
      },
    },
    'removeUselessDefs',
    'removeScripts',
    'sortAttrs',
  ],
};
